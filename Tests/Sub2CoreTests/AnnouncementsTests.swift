import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private func decimal(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }
private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }
private func fields(_ items: [URLQueryItem]) -> [String: String] { Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }) }
private func sentFields(_ request: URLRequest?) -> [String: String] {
    fields(request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? [])
}
private func sortedJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return text(try encoder.encode(value))
}
private func announcementClient(_ transport: ScriptedTransport, clock: RequestClock = .immediate,
                                credential: Credential = .adminKey("fixture")) -> APIClient {
    APIClient(server: stubServer(), credential: credential, deviceID: stubDeviceID, transport: transport, requestClock: clock)
}
/// The reason of the validation error thrown, nil when nothing is thrown.
private func rejectedReason(_ operation: () throws -> Void) -> String? {
    do { try operation(); return nil } catch { return (error as? APIError)?.reason ?? "no reason" }
}
private let hanzi66 = String(repeating: "公", count: 66), hanzi67 = String(repeating: "公", count: 67)
private let createKey = UUID(uuidString: "5B6C7D8E-9FA0-4B1C-8D2E-3F4A5B6C7D8E")!
private let createKeyText = "5b6c7d8e-9fa0-4b1c-8d2e-3f4a5b6c7d8e"
private let createRequest = AnnouncementCreateRequest(title: "标题", content: "正文", status: .active, notifyMode: .popup)
private let createdJSON = #"{"id":21,"title":"标题","content":"正文","status":"active","notify_mode":"popup","targeting":{},"created_at":"2026-10-17T01:00:00Z","updated_at":"2026-10-17T01:00:00Z"}"#
private let fullAnnouncementJSON = #"""
{"id":7,"title":"维护通知","content":"## 安排\n- 周五","status":"active","notify_mode":"popup",
 "targeting":{"any_of":[{"all_of":[{"type":"subscription","operator":"in","group_ids":[3,5]},{"type":"balance","operator":"lt","value":5}]},
                        {"all_of":[{"type":"balance","operator":"gte","value":"100.5"}]}]},
 "starts_at":"2026-10-16T08:00:00+08:00","ends_at":"2026-10-18T06:00:00.123456789Z","created_by":1,"updated_by":2,
 "created_at":"2026-10-15T10:00:00Z","updated_at":"2026-10-16T01:05:00Z",
 "read_stats":{"eligible_count":1036,"read_count":412,"eligible_read_count":410}}
"""#
private let summaryJSON = #"{"announcement_id":7,"total_users":1036,"eligible_count":1036,"read_count":412,"eligible_read_count":410,"computed_at":"2026-10-17T01:41:00Z"}"#
private let readRowsJSON = #"""
{"items":[{"user_id":42,"email":"wang@example.invalid","username":"小王","balance":12.4,"eligible":true,"read_at":"2026-10-16T00:12:00Z"},
          {"user_id":43,"email":"li@example.invalid","balance":0,"eligible":false}],"total":2,"page":1,"page_size":50,"pages":1}
"""#

// MARK: Decoding (60 §15.2, §16.2, §18.2)

@Test func announcementDecodesFullDTO() throws {
    let item = try JSONDecoder().decode(Announcement.self, from: Data(fullAnnouncementJSON.utf8))
    #expect(item.id == 7); #expect(item.title == "维护通知"); #expect(item.content == "## 安排\n- 周五")
    #expect(item.status == .active); #expect(item.notifyMode == .popup)
    let targeting = AnnouncementTargeting(anyOf: [
        AnnouncementConditionGroup(allOf: [.subscription(groupIDs: [3, 5]), .balance("lt", value: 5)]),
        AnnouncementConditionGroup(allOf: [.balance("gte", value: decimal("100.5"))]),
    ])
    #expect(item.targeting == targeting)
    #expect(item.startsAt == ServerTime.parseTimestamp("2026-10-16T00:00:00Z"))
    let ends = try #require(ServerTime.parseTimestamp("2026-10-18T06:00:00.123456789Z"))
    #expect(item.endsAt == ends)
    #expect(item.createdBy == 1); #expect(item.updatedBy == 2)
    #expect(item.createdAt == ServerTime.parseTimestamp("2026-10-15T10:00:00Z"))
    #expect(item.updatedAt == ServerTime.parseTimestamp("2026-10-16T01:05:00Z"))
    #expect(item.readStats == AnnouncementReadStats(eligibleCount: 1_036, readCount: 412, eligibleReadCount: 410))
}

@Test func announcementToleratesMissingAndUnknownFields() throws {
    let bare = try JSONDecoder().decode(Announcement.self, from: Data(#"{"id":3}"#.utf8))
    #expect(bare == Announcement(id: 3, status: nil))
    #expect(bare.title.isEmpty); #expect(bare.content.isEmpty); #expect(bare.notifyMode == .silent); #expect(bare.targeting == .everyone)
    #expect(bare.startsAt == nil); #expect(bare.endsAt == nil); #expect(bare.createdAt == nil); #expect(bare.readStats == nil)
    let odd = #"{"id":4,"status":"scheduled","notify_mode":"loud","targeting":null,"read_stats":{"eligible_count":3}}"#
    let item = try JSONDecoder().decode(Announcement.self, from: Data(odd.utf8))
    #expect(item.status == nil); #expect(item.notifyMode == .silent); #expect(item.targeting.isEveryone); #expect(item.readStats == nil)
    let page = try JSONDecoder().decode(Page<Announcement>.self, from: Data(#"{"items":[{"id":1},{"id":2,"title":"t"}],"page":1,"page_size":20}"#.utf8))
    #expect(page.total == nil); #expect(page.items.map(\.id) == [1, 2])
}

@Test func announcementTargetingDecodesBackendShapes() throws {
    func decode(_ json: String) throws -> AnnouncementTargeting { try JSONDecoder().decode(AnnouncementTargeting.self, from: Data(json.utf8)) }
    #expect(try decode("{}") == .everyone); #expect(try decode(#"{"any_of":null}"#) == .everyone)
    #expect(try decode(#"{"any_of":[]}"#).isEveryone)
    let zero = try decode(#"{"any_of":[{"all_of":[{"type":"balance","operator":"eq"}]}]}"#)
    let condition = try #require(zero.anyOf.first?.allOf.first)
    #expect(condition.value == nil); #expect(condition.effectiveValue == 0); #expect(condition.isValid)
    let number = try decode(#"{"any_of":[{"all_of":[{"type":"balance","operator":"gt","value":5.5}]}]}"#)
    let string = try decode(#"{"any_of":[{"all_of":[{"type":"balance","operator":"gt","value":"5.5"}]}]}"#)
    #expect(number.anyOf[0].allOf[0].value == decimal("5.5")); #expect(number == string)
    let unknown = try decode(#"{"any_of":[{"all_of":[{"type":"role","operator":"in","group_ids":[1]}]}]}"#)
    #expect(unknown.anyOf[0].allOf[0].type == "role"); #expect(!unknown.anyOf[0].allOf[0].isValid)
    #expect(!unknown.isEveryone); #expect(!unknown.isValid)
    let subscription = try decode(#"{"any_of":[{"all_of":[{"type":"subscription","operator":"in","group_ids":[3,5]}]}]}"#)
    #expect(subscription == .single(.subscription(groupIDs: [3, 5]))); #expect(subscription.anyOf[0].allOf[0].operator == "in")
    #expect(throws: (any Error).self) { _ = try decode(#"{"any_of":"everyone"}"#) }
}

@Test func announcementTargetingEncodesSameShapeAsBackend() throws {
    #expect(try sortedJSON(AnnouncementTargeting.everyone) == "{}")
    #expect(try sortedJSON(AnnouncementTargeting.single(.balance("lt", value: 5)))
            == #"{"any_of":[{"all_of":[{"operator":"lt","type":"balance","value":5}]}]}"#)
    #expect(try sortedJSON(AnnouncementTargeting.single(.subscription(groupIDs: [3, 5])))
            == #"{"any_of":[{"all_of":[{"group_ids":[3,5],"operator":"in","type":"subscription"}]}]}"#)
    let full = try JSONDecoder().decode(Announcement.self, from: Data(fullAnnouncementJSON.utf8)).targeting
    #expect(try JSONDecoder().decode(AnnouncementTargeting.self, from: JSONEncoder().encode(full)) == full)
    #expect(full.isValid); #expect(AnnouncementTargeting.everyone.isValid); #expect(AnnouncementTargeting.single(.balance("gte", value: 1)).isValid)
    let group = AnnouncementConditionGroup(allOf: [.balance("lt", value: 5)])
    #expect(AnnouncementTargeting(anyOf: Array(repeating: group, count: 50)).isValid)
    let invalid: [AnnouncementTargeting] = [
        .single(.subscription(groupIDs: [])), .single(.subscription(groupIDs: [0])),
        .single(AnnouncementCondition(type: "balance", operator: "ne", value: 1)),
        .single(AnnouncementCondition(type: "subscription", operator: "gt", groupIDs: [3])),
        AnnouncementTargeting(anyOf: [AnnouncementConditionGroup(allOf: [])]),
        AnnouncementTargeting(anyOf: Array(repeating: group, count: 51)),
        AnnouncementTargeting(anyOf: [AnnouncementConditionGroup(allOf: Array(repeating: .balance("lt", value: 5), count: 51))]),
    ]
    for targeting in invalid { #expect(!targeting.isValid) }
}

// MARK: Write bodies (60 §17.2, §17.4)

@Test func announcementCreateBodyIsSortedAndStable() throws {
    #expect(text(try createRequest.requestBody()) == #"{"content":"正文","notify_mode":"popup","status":"active","targeting":{},"title":"标题"}"#)
    let starts = Date(timeIntervalSince1970: 1_792_108_800.9), ends = Date(timeIntervalSince1970: 1_792_281_600)
    let scheduled = AnnouncementCreateRequest(title: " 标题 ", content: "正文", targeting: .single(.subscription(groupIDs: [3])),
                                              startsAt: starts, endsAt: ends)
    #expect(text(try scheduled.requestBody())
            == #"{"content":"正文","ends_at":1792281600,"notify_mode":"silent","starts_at":1792108800,"status":"draft","targeting":{"any_of":[{"all_of":[{"group_ids":[3],"operator":"in","type":"subscription"}]}]},"title":" 标题 "}"#)
    #expect(try scheduled.requestBody() == scheduled.requestBody())
}

@Test func announcementCreateValidationMirrorsBackend() async throws {
    func create(title: String = "标题", content: String = "正文", targeting: AnnouncementTargeting = .everyone,
                startsAt: Date? = nil, endsAt: Date? = nil) -> AnnouncementCreateRequest {
        AnnouncementCreateRequest(title: title, content: content, targeting: targeting, startsAt: startsAt, endsAt: endsAt)
    }
    #expect(rejectedReason { try create(title: " \n ").validate() } == "ANNOUNCEMENT_TITLE_INVALID")
    #expect(rejectedReason { try create(title: hanzi66).validate() } == nil)
    #expect(rejectedReason { try create(title: "  " + hanzi66 + " ").validate() } == nil)
    #expect(rejectedReason { try create(title: hanzi67).validate() } == "ANNOUNCEMENT_TITLE_INVALID")
    #expect(rejectedReason { try create(content: "  \n").validate() } == "ANNOUNCEMENT_CONTENT_REQUIRED")
    #expect(rejectedReason { try create(targeting: .single(.subscription(groupIDs: []))).validate() } == "ANNOUNCEMENT_INVALID_TARGET")
    let start = Date(timeIntervalSince1970: 1_792_108_800)
    let ranges: [(Date?, Date?)] = [(start, start), (start, start.addingTimeInterval(-60)), (start, start.addingTimeInterval(0.5)),
                                    (Date(timeIntervalSince1970: -10), nil), (nil, Date(timeIntervalSince1970: 253_402_300_800))]
    for (startsAt, endsAt) in ranges {
        #expect(rejectedReason { try create(startsAt: startsAt, endsAt: endsAt).validate() } == "ANNOUNCEMENT_TIME_RANGE_INVALID")
    }
    #expect(rejectedReason { try create(startsAt: start, endsAt: start.addingTimeInterval(1)).validate() } == nil)
    #expect(throws: APIError.self) { _ = try create(title: "").requestBody() }

    let transport = ScriptedTransport { _ in okReply(createdJSON) }
    let client = announcementClient(transport)
    for supports in [true, false] {
        let error = await thrownAPIError {
            _ = try await client.createAnnouncement(create(title: ""), idempotencyKey: createKey, supportsIdempotentCreate: supports)
        }
        #expect(error?.kind == .validation); #expect(error?.reason == "ANNOUNCEMENT_TITLE_INVALID")
    }
    #expect(await transport.requests.isEmpty)
}

@Test func announcementUpdateCarriesOnlyChangedKeys() async throws {
    #expect(text(try AnnouncementUpdateRequest.status(.active).requestBody()) == #"{"status":"active"}"#)
    #expect(text(try AnnouncementUpdateRequest.status(.archived).requestBody()) == #"{"status":"archived"}"#)
    #expect(text(try AnnouncementUpdateRequest(title: "新标题", targeting: .everyone).requestBody()) == #"{"targeting":{},"title":"新标题"}"#)
    let ends = Date(timeIntervalSince1970: 1_792_281_600.7)
    #expect(text(try AnnouncementUpdateRequest(startsAt: .clear, endsAt: .at(ends)).requestBody()) == #"{"ends_at":1792281600,"starts_at":0}"#)
    #expect(text(try AnnouncementUpdateRequest(content: "正文", notifyMode: .popup).requestBody()) == #"{"content":"正文","notify_mode":"popup"}"#)
    #expect(AnnouncementUpdateRequest().isEmpty); #expect(!AnnouncementUpdateRequest.status(.draft).isEmpty)
    #expect(throws: APIError.self) { try AnnouncementUpdateRequest().validate() }
    #expect(rejectedReason { try AnnouncementUpdateRequest(title: hanzi67).validate() } == "ANNOUNCEMENT_TITLE_INVALID")
    #expect(rejectedReason { try AnnouncementUpdateRequest(content: " ").validate() } == "ANNOUNCEMENT_CONTENT_REQUIRED")
    #expect(rejectedReason { try AnnouncementUpdateRequest(targeting: .single(.balance("ne", value: 1))).validate() } == "ANNOUNCEMENT_INVALID_TARGET")
    #expect(rejectedReason { try AnnouncementUpdateRequest(startsAt: .at(ends), endsAt: .at(ends)).validate() } == "ANNOUNCEMENT_TIME_RANGE_INVALID")
    #expect(rejectedReason { try AnnouncementUpdateRequest(startsAt: .at(Date(timeIntervalSince1970: 0))).validate() } == "ANNOUNCEMENT_TIME_RANGE_INVALID")
    #expect(rejectedReason { try AnnouncementUpdateRequest(startsAt: .clear, endsAt: .clear).validate() } == nil)

    let transport = ScriptedTransport { _ in okReply(fullAnnouncementJSON) }
    let client = announcementClient(transport)
    let empty = await thrownAPIError { _ = try await client.updateAnnouncement(id: 7, AnnouncementUpdateRequest()) }
    #expect(empty?.kind == .validation); #expect(empty?.reason == nil)
    let long = await thrownAPIError { _ = try await client.updateAnnouncement(id: 7, AnnouncementUpdateRequest(title: hanzi67)) }
    #expect(long?.reason == "ANNOUNCEMENT_TITLE_INVALID")
    #expect(await transport.requests.isEmpty)
}

// MARK: Queries (60 §15.2, §18.2, U44)

@Test func announcementListQueryItemsFollowCapability() throws {
    #expect(AnnouncementListQuery.defaultPageSize == 20)
    #expect(fields(try AnnouncementListQuery().queryItems(page: 1)) == ["page": "1", "page_size": "20", "sort_by": "created_at", "sort_order": "desc"])
    let filtered = AnnouncementListQuery(status: .draft, search: "  维护  ", includeReadStats: true)
    #expect(fields(try filtered.queryItems(page: 3)) == ["page": "3", "page_size": "20", "sort_by": "created_at", "sort_order": "desc",
                                                        "status": "draft", "search": "维护", "include_read_stats": "true"])
    let long = fields(try AnnouncementListQuery(search: " " + hanzi67 + " ").queryItems(page: 1))["search"]
    #expect(long == hanzi66); #expect(long?.utf8.count == 198)
    let mixed = fields(try AnnouncementListQuery(search: String(repeating: "a", count: 199) + "公").queryItems(page: 1))["search"]
    #expect(mixed == String(repeating: "a", count: 199))
    #expect(fields(try AnnouncementListQuery(search: "   ").queryItems(page: 1))["search"] == nil)
    #expect(fields(try AnnouncementListQuery(pageSize: 5_000).queryItems(page: 1))["page_size"] == "1000")
    #expect(fields(try AnnouncementListQuery(pageSize: 0).queryItems(page: 1))["page_size"] == "1")
    #expect(throws: APIError.self) { _ = try AnnouncementListQuery().queryItems(page: 0) }
}

@Test func announcementReadStatusQueryWithReadStatsCapability() throws {
    typealias Sort = AnnouncementReadStatusQuery.Sort
    let base = AnnouncementReadStatusQuery(supportsReadStats: true)
    #expect(fields(try base.queryItems(page: 1)) == ["page": "1", "page_size": "50", "sort_by": "email", "sort_order": "asc"])
    #expect(!base.isFiltered); #expect(base.effectivePageSize == 50)
    var query = base
    query.readState = .read
    #expect(fields(try query.queryItems(page: 2))["read_state"] == "read"); #expect(query.isFiltered)
    query.readState = .unread; query.eligibleOnly = true
    let sent = fields(try query.queryItems(page: 1))
    #expect(sent["read_state"] == "unread"); #expect(sent["eligible"] == "true")
    let orders: [(Sort, String, String)] = [(.email, "email", "asc"), (.username, "username", "asc"), (.balance, "balance", "desc"), (.readAt, "read_at", "desc")]
    for (sort, sortBy, order) in orders {
        var sorted = base; sorted.sort = sort
        let items = fields(try sorted.queryItems(page: 1))
        #expect(items["sort_by"] == sortBy); #expect(items["sort_order"] == order); #expect(!sorted.isFiltered); #expect(sorted.effectiveSort == sort)
    }
    var searched = base; searched.search = "  wang  "
    #expect(fields(try searched.queryItems(page: 1))["search"] == "wang"); #expect(searched.isFiltered)
    var eligible = base; eligible.eligibleOnly = true
    #expect(eligible.isFiltered); #expect(fields(try eligible.queryItems(page: 1))["read_state"] == nil)
    var large = base; large.pageSize = 5_000
    #expect(large.effectivePageSize == 1_000)
    #expect(Sort.available(supportsReadStats: true) == Sort.allCases)
    #expect(Sort.allCases.map(\.requiresReadStats) == [false, false, false, true])
    #expect(throws: APIError.self) { _ = try base.queryItems(page: 0) }
}

@Test func announcementReadStatusQueryWithoutReadStatsCapability() throws {
    var query = AnnouncementReadStatusQuery(readState: .unread, eligibleOnly: true, sort: .readAt, supportsReadStats: false)
    #expect(query.effectiveSort == .email)
    #expect(fields(try query.queryItems(page: 1)) == ["page": "1", "page_size": "50", "sort_by": "email", "sort_order": "asc"])
    #expect(!query.isFiltered)
    query.search = "wang"
    #expect(query.isFiltered)
    for (requested, sent) in [(10, 20), (80, 50), (50, 50), (20, 20), (30, 30)] {
        var sized = query; sized.pageSize = requested
        #expect(sized.effectivePageSize == sent); #expect(fields(try sized.queryItems(page: 1))["page_size"] == String(sent))
    }
    query.sort = .balance
    #expect(fields(try query.queryItems(page: 1))["sort_order"] == "desc")
    #expect(AnnouncementReadStatusQuery.Sort.available(supportsReadStats: false) == [.email, .username, .balance])
    #expect(AnnouncementReadStatusQuery.pageSizeWithReadStats == 50); #expect(AnnouncementReadStatusQuery.legacyPageSizes == 20...50)
}

// MARK: Reads (60 §15.2, §16.2, §18.2, H07 退路)

@Test func announcementReadEndpointsUseBackendPathsWithoutConditionalHeaders() async throws {
    let transport = ScriptedTransport { request in
        let path = request.url?.path ?? ""
        if path.hasSuffix("/read-summary") { return okReply(summaryJSON, headers: ["ETag": "\"r1\""]) }
        if path.hasSuffix("/read-status") { return okReply(readRowsJSON) }
        if path.hasSuffix("/announcements/7") { return okReply(fullAnnouncementJSON) }
        return okReply(#"{"items":[\#(fullAnnouncementJSON)],"total":1,"page":1,"page_size":20,"pages":1}"#, headers: ["ETag": "\"l1\""])
    }
    let client = APIClient(server: stubServer(), credential: .adminKey("fixture"), deviceID: stubDeviceID, transport: transport, requestClock: .immediate,
                           cacheIdentity: ConditionalCache.Identity(userID: 1, authMethod: "admin_api_key"), conditionalCache: ConditionalCache())
    let page = try await client.announcements(page: 1, query: AnnouncementListQuery(includeReadStats: true))
    #expect(page.items.map(\.id) == [7]); #expect(page.total == 1)
    _ = try await client.announcements(page: 1, query: AnnouncementListQuery(includeReadStats: true))
    #expect(try await client.announcement(id: 7, includeReadStats: true).readStats?.eligibleReadCount == 410)
    _ = try await client.announcement(id: 7, includeReadStats: false)
    let summary = try await client.announcementReadSummary(id: 7)
    #expect(summary == AnnouncementReadSummary(announcementID: 7, totalUsers: 1_036, eligibleCount: 1_036, readCount: 412, eligibleReadCount: 410,
                                                computedAt: ServerTime.parseTimestamp("2026-10-17T01:41:00Z")))
    #expect(summary.readButIneligible == 2)
    let rows = try await client.announcementReadStatus(id: 7, page: 1, query: AnnouncementReadStatusQuery(readState: .read, supportsReadStats: true))
    #expect(rows.items[0] == AnnouncementReadStatusRow(userID: 42, email: "wang@example.invalid", username: "小王", balance: decimal("12.4"),
                                                       eligible: true, readAt: ServerTime.parseTimestamp("2026-10-16T00:12:00Z")))
    #expect(rows.items[1].username.isEmpty); #expect(rows.items[1].readAt == nil); #expect(!rows.items[1].eligible); #expect(rows.items[1].balance == 0)
    #expect(try await client.recentAnnouncements(title: "  维护通知 ").map(\.id) == [7])

    let requests = await transport.requests
    let list = "/api/v1/admin/announcements", detail = list + "/7"
    #expect(requests.map { $0.url?.path ?? "" } == [list, list, detail, detail, detail + "/read-summary", detail + "/read-status", list])
    #expect(requests.allSatisfy { $0.httpMethod == "GET" && sentHeader($0, "If-None-Match") == nil })
    #expect(sentFields(requests[0]) == ["page": "1", "page_size": "20", "sort_by": "created_at", "sort_order": "desc", "include_read_stats": "true"])
    #expect(sentFields(requests[2]) == ["include_read_stats": "true"]); #expect(sentFields(requests[3]).isEmpty); #expect(sentFields(requests[4]).isEmpty)
    #expect(sentFields(requests[5]) == ["page": "1", "page_size": "50", "sort_by": "email", "sort_order": "asc", "read_state": "read"])
    #expect(sentFields(requests[6]) == ["page": "1", "page_size": "5", "search": "维护通知", "sort_by": "created_at", "sort_order": "desc"])
    #expect(!ConditionalCache.supports(method: "GET", path: "admin/announcements"))

    let invalidCalls: [@Sendable () async throws -> Void] = [
        { _ = try await client.announcement(id: 0, includeReadStats: false) }, { _ = try await client.announcementReadSummary(id: 0) },
        { _ = try await client.announcementReadStatus(id: 0, page: 1, query: AnnouncementReadStatusQuery(supportsReadStats: true)) },
        { _ = try await client.updateAnnouncement(id: 0, .status(.active)) }, { _ = try await client.deleteAnnouncement(id: 0) },
    ]
    for call in invalidCalls { #expect(await thrownAPIError(call)?.kind == .validation) }
    #expect(await transport.requests.count == 7)
}

private func countsReply(_ request: URLRequest) -> HTTPResponse {
    let totals = ["": 5, "active": 2, "draft": 1, "archived": 2]
    let total = totals[sentFields(request)["status"] ?? ""] ?? 0
    return okReply(#"{"items":[{"id":1}],"total":\#(total),"page":1,"page_size":1,"pages":\#(total)}"#)
}

@Test(.timeLimit(.minutes(1))) func announcementCountsRunsFourQueriesConcurrently() async throws {
    let gate = OpenGate(), arrivals = CallCounter()
    let transport = ScriptedTransport { request in
        if arrivals.next() == 4 { await gate.open() }
        await gate.wait()
        return countsReply(request)
    }
    let counts = try await announcementClient(transport).announcementCounts()
    #expect(counts == AnnouncementCounts(all: 5, active: 2, draft: 1, archived: 2))
    let requests = await transport.requests
    #expect(requests.count == 4)
    #expect(Set(requests.map { sentFields($0)["status"] ?? "all" }) == ["all", "active", "draft", "archived"])
    for request in requests {
        let sent = sentFields(request)
        #expect(request.url?.path == "/api/v1/admin/announcements"); #expect(sent["page"] == "1"); #expect(sent["page_size"] == "1")
        #expect(sent["include_read_stats"] == nil)
    }
    let order: [AnnouncementStatus?] = [nil, .active, .draft, .archived]
    #expect(order.map { counts.count(for: $0) } == [5, 2, 1, 2])
}

@Test func announcementCountsKeepPartialResultsAndThrowWhenAllFail() async throws {
    let partial = ScriptedTransport { request in
        sentFields(request)["status"] == "draft" ? HTTPResponse(statusCode: 502, data: Data("bad gateway".utf8)) : countsReply(request)
    }
    #expect(try await announcementClient(partial).announcementCounts() == AnnouncementCounts(all: 5, active: 2, draft: nil, archived: 2))
    #expect(await partial.requests.filter { sentFields($0)["status"] == "draft" }.count == 3)
    let failing = ScriptedTransport { _ in errorReply(500) }
    #expect(await thrownAPIError { _ = try await announcementClient(failing).announcementCounts() }?.statusCode == 500)
    let noTotal = ScriptedTransport { _ in okReply(#"{"items":[],"page":1,"page_size":1}"#) }
    #expect(try await announcementClient(noTotal).announcementCounts() == AnnouncementCounts(all: nil, active: nil, draft: nil, archived: nil))
}

@Test(.timeLimit(.minutes(1))) func announcementCountsPropagateCancellation() async throws {
    let arrived = OpenGate(), arrivals = CallCounter()
    let transport = ScriptedTransport { _ in
        if arrivals.next() == 4 { await arrived.open() }
        try await Task.sleep(for: .seconds(30))
        return okReply(#"{"items":[],"total":1,"page":1,"page_size":1}"#)
    }
    let client = announcementClient(transport)
    let task = Task { try await client.announcementCounts() }
    await arrived.wait()
    task.cancel()
    do { _ = try await task.value; Issue.record("expected the counts to be cancelled") }
    catch { #expect(error is CancellationError) }
}

// MARK: Writes (60 §16.4, §17.4, R04, H07)

@Test func announcementKeyedCreateFollowsExecutorWithCapability() async throws {
    let transport = ScriptedTransport { _ in okReply(createdJSON, headers: ["X-Idempotency-Replayed": "true"]) }
    let outcome = try await announcementClient(transport).createAnnouncement(createRequest, idempotencyKey: createKey, supportsIdempotentCreate: true)
    #expect(outcome.value.id == 21); #expect(outcome.replayed)
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "POST"); #expect(request.url?.path == "/api/v1/admin/announcements")
    #expect(sentHeader(request, "Idempotency-Key") == createKeyText); #expect(sentHeader(request, "X-Request-ID") == createKeyText)
    #expect(request.httpBody == (try createRequest.requestBody())); #expect(request.timeoutInterval == 35)

    let recorder = SleepRecorder()
    let flaky = ScriptedTransport(script: [.fail(URLError(.timedOut)), .reply(okReply(createdJSON))])
    _ = try await announcementClient(flaky, clock: .recording(recorder)).createAnnouncement(createRequest, idempotencyKey: createKey,
                                                                                         supportsIdempotentCreate: true)
    let attempts = await flaky.requests
    #expect(attempts.count == 2); #expect(attempts[0].httpBody == attempts[1].httpBody)
    #expect(attempts.allSatisfy { sentHeader($0, "Idempotency-Key") == createKeyText })
    #expect(await recorder.durations == [.seconds(2)])

    let waits = SleepRecorder()
    let busy = ScriptedTransport(script: [.reply(errorReply(409, reason: "IDEMPOTENCY_IN_PROGRESS", headers: ["Retry-After": "3"])),
                                          .reply(okReply(createdJSON))])
    _ = try await announcementClient(busy, clock: .recording(waits)).createAnnouncement(createRequest, idempotencyKey: createKey,
                                                                                      supportsIdempotentCreate: true)
    #expect(await waits.durations == [.seconds(3)]); #expect(await busy.requests.count == 2)

    let conflict = ScriptedTransport { _ in errorReply(409, reason: "IDEMPOTENCY_KEY_CONFLICT") }
    do {
        _ = try await announcementClient(conflict).createAnnouncement(createRequest, idempotencyKey: createKey, supportsIdempotentCreate: true)
        Issue.record("expected a key conflict")
    } catch { #expect((error as? KeyedWriteFailure)?.disposition == .needsNewKey(.keyConflict)) }
    #expect(await conflict.requests.count == 1)
}

@Test func announcementLegacyCreateSendsExactlyOnce() async throws {
    let ok = ScriptedTransport { _ in okReply(createdJSON) }
    let outcome = try await announcementClient(ok).createAnnouncement(createRequest, idempotencyKey: createKey, supportsIdempotentCreate: false)
    #expect(outcome.value.id == 21); #expect(!outcome.replayed)
    let sent = try #require(await ok.requests.first)
    #expect(sentHeader(sent, "Idempotency-Key") == createKeyText); #expect(sentHeader(sent, "X-Request-ID") == createKeyText)
    #expect(sent.httpBody == (try createRequest.requestBody())); #expect(sent.httpMethod == "POST")

    let unconfirmed: [(ScriptStep, KeyedWriteFailure.UnconfirmedCause)] = [
        (.fail(URLError(.timedOut)), .transport),
        (.reply(HTTPResponse(statusCode: 502, data: Data("<html>bad gateway</html>".utf8))), .transport),
        (.reply(HTTPResponse(statusCode: 200, data: Data("<html>ok</html>".utf8))), .unreadableResponse),
        (.reply(okReply(#""not an announcement""#)), .unreadableResponse),
        (.reply(errorReply(409, reason: "IDEMPOTENCY_IN_PROGRESS")), .stillProcessing),
    ]
    for (step, cause) in unconfirmed {
        let recorder = SleepRecorder()
        let transport = ScriptedTransport(script: [step, .reply(okReply(createdJSON))])
        do {
            _ = try await announcementClient(transport, clock: .recording(recorder)).createAnnouncement(createRequest, idempotencyKey: createKey,
                                                                                                    supportsIdempotentCreate: false)
            Issue.record("expected an unconfirmed create")
        } catch {
            let failure = error as? KeyedWriteFailure
            #expect(failure?.disposition == .unconfirmed(cause, retryNotBefore: nil)); #expect(failure?.key == createKeyText)
        }
        #expect(await transport.requests.count == 1); #expect(await recorder.durations.isEmpty)
    }
    for (status, reason) in [(400, "ANNOUNCEMENT_TITLE_INVALID"), (403, "ACCESS_TOKEN_READ_ONLY")] {
        let transport = ScriptedTransport(script: [.reply(errorReply(status, reason: reason)), .reply(okReply(createdJSON))])
        let error = await thrownAPIError {
            _ = try await announcementClient(transport).createAnnouncement(createRequest, idempotencyKey: createKey, supportsIdempotentCreate: false)
        }
        #expect(error?.statusCode == status); #expect(error?.reason == reason); #expect(await transport.requests.count == 1)
    }
}

@Test func announcementLegacyCreateResendsSameBytesAfterTokenRefresh() async throws {
    let transport = ScriptedTransport { request in
        if isRefresh(request) { return okReply(stubRefreshJSON) }
        if sentHeader(request, "Authorization") == "Bearer old-access" { return errorReply(401, reason: "TOKEN_EXPIRED") }
        return okReply(createdJSON)
    }
    let client = announcementClient(transport, credential: stubTokens())
    let outcome = try await client.createAnnouncement(createRequest, idempotencyKey: createKey, supportsIdempotentCreate: false)
    #expect(outcome.value.id == 21)
    let requests = await transport.requests, writes = requests.filter { !isRefresh($0) }
    #expect(writes.count == 2); #expect(requests.filter(isRefresh).count == 1)
    #expect(writes[0].httpBody == writes[1].httpBody); #expect(sentHeader(writes[1], "Authorization") == "Bearer new-access")
    for name in ["Idempotency-Key", "X-Request-ID"] { #expect(writes.allSatisfy { sentHeader($0, name) == createKeyText }) }
}

@Test func announcementUpdateAndDeleteAreUnkeyedAndSentOnce() async throws {
    let badGateway = HTTPResponse(statusCode: 502, data: Data("bad gateway".utf8))
    let transport = ScriptedTransport(script: [.reply(okReply(fullAnnouncementJSON)), .reply(badGateway), .reply(okReply(fullAnnouncementJSON))])
    let client = announcementClient(transport)
    #expect(try await client.updateAnnouncement(id: 7, .status(.active)).id == 7)
    let put = try #require(await transport.requests.first)
    #expect(put.httpMethod == "PUT"); #expect(put.url?.path == "/api/v1/admin/announcements/7")
    #expect(put.httpBody.map(text) == #"{"status":"active"}"#)
    #expect(sentHeader(put, "Idempotency-Key") == nil); #expect(sentHeader(put, "X-Request-ID") != nil); #expect(put.timeoutInterval == 30)
    #expect(await thrownAPIError { _ = try await client.updateAnnouncement(id: 7, .status(.archived)) }?.statusCode == 502)
    #expect(await transport.requests.count == 2)

    let deletes = ScriptedTransport(script: [.reply(okReply(#"{"message":"Announcement deleted successfully"}"#)),
                                             .reply(errorReply(404, reason: "ANNOUNCEMENT_NOT_FOUND")), .reply(errorReply(404, reason: "RESOURCE_NOT_FOUND")),
                                             .reply(badGateway), .reply(okReply(#"{"message":"ok"}"#))])
    let deleter = announcementClient(deletes)
    #expect(try await deleter.deleteAnnouncement(id: 7) == .deleted)
    let delete = try #require(await deletes.requests.first)
    #expect(delete.httpMethod == "DELETE"); #expect(delete.url?.path == "/api/v1/admin/announcements/7")
    #expect(sentHeader(delete, "Idempotency-Key") == nil)
    #expect(try await deleter.deleteAnnouncement(id: 7) == .alreadyGone)
    #expect(await thrownAPIError { _ = try await deleter.deleteAnnouncement(id: 7) }?.reason == "RESOURCE_NOT_FOUND")
    #expect(await thrownAPIError { _ = try await deleter.deleteAnnouncement(id: 7) }?.statusCode == 502)
    #expect(await deletes.requests.count == 4)
}
