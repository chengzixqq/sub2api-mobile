import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private actor ManagedAccountTransport: HTTPTransport {
    private var captured: [URLRequest] = []
    let reply: HTTPResponse
    let fails: Bool
    init(reply: HTTPResponse = HTTPResponse(statusCode: 200, data: Data(#"{"code":0,"data":{"success":1,"failed":1,"results":[{"account_id":1,"success":true},{"account_id":2,"success":false,"error":"private upstream details"}]}}"#.utf8)), fails: Bool = false) { self.reply = reply; self.fails = fails }
    func data(for request: URLRequest) async throws -> HTTPResponse {
        captured.append(request)
        if fails { throw URLError(.timedOut) }
        return reply
    }
    func stream(for request: URLRequest) async throws -> HTTPStreamResponse { throw APIError.invalidResponse }
    func requests() -> [URLRequest] { captured }
}
private func managedAccountServer() -> ServerProfile {
    ServerProfile(name: "账号管理测试", baseURL: URL(string: "https://accounts.example.invalid")!, authentication: .adminKey)
}

private func sentFields(_ query: AccountListQuery, page: Int = 1) throws -> [String: String] {
    Dictionary(uniqueKeysWithValues: try query.queryItems(page: page).map { ($0.name, $0.value ?? "") })
}

@Test func accountListQueryEncodesEveryParameterWithListQuery() throws {
    let query = AccountListQuery(search: " Alpha & B ", platform: "openai", type: "apikey", group: .id(10),
                                 statuses: [.tempUnschedulable, .overloaded, .rateLimited], sort: .urgency, descending: true,
                                 pageSize: 200, includeCounts: true, includeSchedulerScore: true, supportsListQuery: true)
    let items = try query.queryItems(page: 3)
    #expect(items.map(\.name) == ["page", "page_size", "lite", "sort_by", "sort_order", "search", "status", "platform", "type", "group", "include_scheduler_score"])
    let fields = try sentFields(query, page: 3)
    #expect(fields["page"] == "3" && fields["page_size"] == "200" && fields["lite"] == "1")
    #expect(fields["sort_by"] == "urgency" && fields["sort_order"] == "desc")
    #expect(fields["search"] == "Alpha & B" && fields["status"] == "overloaded,rate_limited,temp_unschedulable")
    #expect(fields["platform"] == "openai" && fields["type"] == "apikey" && fields["group"] == "10")
    #expect(fields["include_scheduler_score"] == "1" && fields["include_counts"] == nil)
    #expect(!query.needsLocalStatusFilter)
    #expect(!AccountSort.allCases.map(\.rawValue).contains("current_rpm"))
    let plain = try sentFields(AccountListQuery(sort: .lastUsed))
    #expect(plain["sort_by"] == "last_used_at" && plain["sort_order"] == "asc" && plain["include_scheduler_score"] == nil)
    #expect(plain["search"] == nil && plain["status"] == nil && plain["platform"] == nil && plain["type"] == nil && plain["group"] == nil)
}

/// R09: counts are asked for on page 1 only.
@Test func includeCountsOnlyOnFirstPage() throws {
    var query = AccountListQuery(includeCounts: true, supportsListQuery: true)
    #expect(try sentFields(query, page: 1)["include_counts"] == "1")
    #expect(try sentFields(query, page: 2)["include_counts"] == nil)
    query.includeCounts = false
    #expect(try sentFields(query, page: 1)["include_counts"] == nil)
}

/// 00 §5 rule 1 / §9.8: an old server gets no new parameter; a single legacy status value is still sent.
@Test func withoutListQueryCapabilityNoNewParametersAreSent() throws {
    let unsent: [Set<AccountStatusFilter>] = [[.needsAttention], [.unschedulable, .inactive], [.schedulableNow], [.overloaded]]
    for statuses in unsent {
        let query = AccountListQuery(statuses: statuses)
        #expect(try sentFields(query)["status"] == nil, "\(statuses)")
        #expect(query.needsLocalStatusFilter, "\(statuses)")
    }
    for single in [AccountStatusFilter.error, .rateLimited] {
        let query = AccountListQuery(statuses: [single])
        #expect(try sentFields(query)["status"] == single.rawValue)
        #expect(!query.needsLocalStatusFilter)
    }
    let legacy = try sentFields(AccountListQuery(sort: .urgency, includeCounts: true))
    #expect(legacy["sort_by"] == "name" && legacy["include_counts"] == nil && legacy["lite"] == "1")
    #expect(!AccountListQuery().needsLocalStatusFilter)
}

/// 20 §1.2: the chips' strings are fixed whatever order the values were picked in.
@Test func statusValuesJoinInFixedOrder() throws {
    let paused = try sentFields(AccountListQuery(statuses: [.inactive, .unschedulable], supportsListQuery: true))
    let pausedAgain = try sentFields(AccountListQuery(statuses: [.unschedulable, .inactive], supportsListQuery: true))
    #expect(paused["status"] == "unschedulable,inactive" && pausedAgain["status"] == paused["status"])
    let limited = try sentFields(AccountListQuery(statuses: [.rateLimited, .tempUnschedulable, .overloaded], supportsListQuery: true))
    #expect(limited["status"] == "overloaded,rate_limited,temp_unschedulable")
    let everything = try sentFields(AccountListQuery(statuses: Set(AccountStatusFilter.allCases), supportsListQuery: true))
    let joined = try #require(everything["status"])
    #expect(joined.split(separator: ",").map(String.init) == AccountStatusFilter.allCases.map(\.rawValue))
    #expect(joined.split(separator: ",").count == 9)
}

/// 00 §4.1: 500 by default, 1–1000 on the wire.
@Test func pageSizeDefaultsTo500AndIsClamped() throws {
    #expect(AccountListQuery.defaultPageSize == 500)
    #expect(try sentFields(AccountListQuery())["page_size"] == "500")
    for (requested, sent) in [(0, "1"), (-5, "1"), (1_001, "1000"), (6, "6"), (5, "5"), (1_000, "1000")] {
        #expect(try sentFields(AccountListQuery(pageSize: requested))["page_size"] == sent, "\(requested)")
    }
}

@Test func groupFilterAndPageValidation() throws {
    #expect(try sentFields(AccountListQuery(group: .ungrouped))["group"] == "ungrouped")
    #expect(try sentFields(AccountListQuery())["group"] == nil)
    for invalid in [AccountGroupFilter.id(0), .id(-1)] {
        let error = #expect(throws: APIError.self) { _ = try AccountListQuery(group: invalid).queryItems(page: 1) }
        #expect(error?.kind == .validation)
    }
    let error = #expect(throws: APIError.self) { _ = try AccountListQuery().queryItems(page: 0) }
    #expect(error?.kind == .validation)
}

@Test func searchIsTrimmedAndCappedAt100UTF8Bytes() throws {
    #expect(try sentFields(AccountListQuery(search: "\n  Alpha \t"))["search"] == "Alpha")
    let capped = try #require(try sentFields(AccountListQuery(search: String(repeating: "汉", count: 60)))["search"])
    #expect(capped == String(repeating: "汉", count: 33) && capped.utf8.count == 99)
    let exact = try #require(try sentFields(AccountListQuery(search: String(repeating: "a", count: 100) + "b"))["search"])
    #expect(exact == String(repeating: "a", count: 100))
    #expect(try sentFields(AccountListQuery(search: " \n "))["search"] == nil)
}

@Test func managedAccountsDecodesPageAndCounts() async throws {
    let item = #"{"id":9,"name":"账号","platform":"openai","type":"apikey","status":"active","schedulable":true}"#
    let counts = #"{"all":1200,"needs_attention":7,"error":2,"overloaded":1,"rate_limited":3,"temp_unschedulable":1,"unschedulable":4,"inactive":5,"schedulable_now":1180}"#
    let replies = [
        "{\"items\":[\(item)],\"total\":1200,\"page\":1,\"page_size\":500,\"pages\":3,\"counts\":\(counts)}",
        "{\"items\":[\(item)],\"total\":1200,\"page\":2,\"page_size\":500,\"counts\":{\"all\":1200}}",
        "{\"items\":[],\"total\":0,\"page\":1,\"page_size\":500}",
        "{\"items\":[],\"total\":0,\"page\":1,\"page_size\":500,\"counts\":\"bad\"}",
        "{\"items\":[],\"total\":null,\"page\":1,\"page_size\":500}"
    ]
    let transport = ScriptedTransport(script: replies.map { .reply(okReply($0)) })
    let client = APIClient(server: managedAccountServer(), credential: .adminKey("fixture"), transport: transport)
    let query = AccountListQuery(includeCounts: true, supportsListQuery: true)
    let first = try await client.managedAccounts(page: 1, query: query)
    #expect(first.items.map(\.id) == [9] && first.total == 1_200 && first.page == 1 && first.pageSize == 500 && first.pages == 3 && first.hasMore)
    #expect(first.counts == AccountListCounts(all: 1_200, needsAttention: 7, error: 2, overloaded: 1, rateLimited: 3, tempUnschedulable: 1,
                                              unschedulable: 4, inactive: 5, schedulableNow: 1_180))
    let sent = try #require(await transport.requests.first)
    let sentURL = try #require(sent.url)
    let expectedItems = try query.queryItems(page: 1)
    #expect(sent.httpMethod == "GET" && sentURL.path == "/api/v1/admin/accounts")
    #expect(URLComponents(url: sentURL, resolvingAgainstBaseURL: false)?.queryItems == expectedItems)
    let second = try await client.managedAccounts(page: 2, query: query)
    #expect(second.pages == 3 && second.hasMore && second.counts == AccountListCounts(all: 1_200) && second.counts?.error == nil)
    let empty = try await client.managedAccounts(page: 1, query: query)
    #expect(empty.counts == nil && empty.pages == 0 && !empty.hasMore)
    let corrupt = try await client.managedAccounts(page: 1, query: query)
    #expect(corrupt.counts == nil && corrupt.total == 0)
    let error = await thrownAPIError { _ = try await client.managedAccounts(page: 1, query: query) }
    #expect(error?.kind == .response)
}

@Test func accountSortUrgencyAndLegacyValues() {
    #expect(AccountSort.urgency.rawValue == "urgency" && AccountSort.urgency.title == "紧急度")
    #expect(AccountSort.allCases.last == .urgency)
    #expect(AccountSort.allCases.dropLast().map(\.rawValue) == ["name", "id", "status", "schedulable", "priority", "rate_multiplier", "last_used_at", "created_at", "expires_at"])
    #expect(AccountStatusFilter.allCases.filter(\.isLegacy) == [.error, .rateLimited, .tempUnschedulable, .unschedulable, .inactive, .active])
}

@Test func accountBatchWritesRejectOldIdentity() async throws {
    let transport = ManagedAccountTransport(fails: true)
    let client = APIClient(server: managedAccountServer(), credential: .adminKey("fixture"), transport: transport)
    let identity = await client.userWriteIdentity()
    await client.cancelAll()
    await #expect(throws: APIError.self) { try await client.refreshManagedAccount(id: 4, identity: identity) }
    #expect(await transport.requests().isEmpty)
}

@Test func bulkAccountSchedulingPreservesPartialFailureAndUnknownRows() async throws {
    let transport = ManagedAccountTransport()
    let client = APIClient(server: managedAccountServer(), credential: .adminKey("fixture"), transport: transport)
    let result = try await client.setAccountsSchedulable(ids: [1, 2], enabled: false, idempotencyKey: nil).value
    #expect(result.outcome(for: 1) == true && result.outcome(for: 2) == false && result.outcome(for: 3) == nil)
    let sent = try #require(await transport.requests().first)
    let json = try #require(JSONSerialization.jsonObject(with: sent.httpBody!) as? [String: Any])
    #expect(json["account_ids"] as? [Int] == [1, 2] && json["schedulable"] as? Bool == false)
    #expect(sent.url?.path == "/api/v1/admin/accounts/bulk-update" && sent.httpMethod == "POST")
    await #expect(throws: APIError.self) { try await client.setAccountsSchedulable(ids: [1, 1], enabled: false, idempotencyKey: nil) }
    await #expect(throws: APIError.self) { try await client.setAccountsSchedulable(ids: Array(1...51), enabled: false, idempotencyKey: nil) }
    #expect(await transport.requests().count == 1)
    let duplicate = try JSONDecoder().decode(AccountBulkReply.self, from: Data(#"{"success":2,"failed":0,"results":[{"account_id":1,"success":true},{"account_id":1,"success":true}]}"#.utf8))
    #expect(duplicate.outcome(for: 1) == nil)
}

// MARK: - Bulk scheduling (S2-07, 20 §8.2)

private func bulkClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: managedAccountServer(), credential: .adminKey("fixture"), deviceID: stubDeviceID, transport: transport, requestClock: .immediate)
}
private let bulkReplyJSON = #"{"success":2,"failed":0,"success_ids":[1,2],"failed_ids":[],"results":[{"account_id":1,"success":true},{"account_id":2,"success":true}]}"#

@Test func keyedBulkSchedulingSendsOneKeyAndRetriesSameBytes() async throws {
    let transport = ScriptedTransport(script: [.fail(URLError(.timedOut)), .reply(okReply(bulkReplyJSON, headers: ["X-Idempotency-Replayed": "true"]))])
    let key = UUID()
    let outcome = try await bulkClient(transport).setAccountsSchedulable(ids: [1, 2], enabled: false, idempotencyKey: key)
    let requests = await transport.requests
    #expect(requests.count == 2)
    for request in requests {
        #expect(sentHeader(request, "Idempotency-Key") == key.uuidString.lowercased() && sentHeader(request, "X-Request-ID") == key.uuidString.lowercased())
        #expect(request.httpBody == requests[0].httpBody && request.timeoutInterval == RequestTimeout.keyedBulk)
    }
    #expect(outcome.value.successIDs == [1, 2] && outcome.replayed)
}

@Test func unkeyedBulkSchedulingIsSentOnceWithoutKey() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(bulkReplyJSON))])
    _ = try await bulkClient(transport).setAccountsSchedulable(ids: [1, 2], enabled: true, idempotencyKey: nil)
    let sent = try #require(await transport.requests.first)
    #expect(sentHeader(sent, "Idempotency-Key") == nil && sent.timeoutInterval == RequestTimeout.unkeyedWrite)
    let requestID = try #require(sentHeader(sent, "X-Request-ID"))
    #expect(requestID == requestID.lowercased() && UUID(uuidString: requestID) != nil)
    let lost = ScriptedTransport(script: [.fail(URLError(.timedOut)), .reply(okReply(bulkReplyJSON))])
    let error = await thrownAPIError { _ = try await bulkClient(lost).setAccountsSchedulable(ids: [1], enabled: true, idempotencyKey: nil) }
    #expect(error?.kind == .transport)
    #expect(await lost.requests.count == 1)
}

@Test func bulkSchedulingValidatesBeforeSending() async throws {
    let transport = ScriptedTransport(script: [.reply(okReply(bulkReplyJSON))])
    let client = bulkClient(transport)
    for ids in [[], [1, 1], [0], [-3], Array(1...51)] {
        let error = await thrownAPIError { _ = try await client.setAccountsSchedulable(ids: ids, enabled: false, idempotencyKey: UUID()) }
        #expect(error?.kind == .validation && error?.localizedDescription == "请选择 1 至 50 个不同账号。", "\(ids)")
    }
    #expect(await transport.requests.isEmpty)
    _ = try await client.setAccountsSchedulable(ids: [1, 2], enabled: false, idempotencyKey: nil)
    let sent = try #require(await transport.requests.first)
    #expect(sent.httpBody == Data(#"{"account_ids":[1,2],"schedulable":false}"#.utf8))
    #expect(sent.url?.path == "/api/v1/admin/accounts/bulk-update" && sent.httpMethod == "POST")
}

@Test func bulkReplyDecodesIDListsAndOutcomeRejectsMissingDuplicateOrContradictoryRows() throws {
    func decode(_ json: String) throws -> AccountBulkReply { try JSONDecoder().decode(AccountBulkReply.self, from: Data(json.utf8)) }
    let full = try decode(#"{"success":1,"failed":1,"success_ids":[1],"failed_ids":[2],"results":[{"account_id":1,"success":true},{"account_id":2,"success":false,"error":"x"}],"long_context_inherited_count":3}"#)
    #expect(full.successIDs == [1] && full.failedIDs == [2] && full.success == 1 && full.failed == 1)
    #expect(full.outcome(for: 1) == true && full.outcome(for: 2) == false && full.outcome(for: 3) == nil)
    let old = try decode(#"{"success":1,"failed":0,"results":[{"account_id":1,"success":true}]}"#)
    #expect(old.successIDs == nil && old.failedIDs == nil && old.outcome(for: 1) == true)
    let bare = try decode("{}")
    #expect(bare.results.isEmpty && bare.success == 0 && bare.failed == 0)
    let row = AccountBulkReply.Item(accountID: 1, success: true)
    #expect(AccountBulkReply(success: 1, failed: 0, successIDs: [], failedIDs: [1], results: [row]).outcome(for: 1) == nil)
    #expect(AccountBulkReply(success: 1, failed: 0, successIDs: [], failedIDs: [], results: [row]).outcome(for: 1) == nil)
    #expect(AccountBulkReply(success: 1, failed: 0, successIDs: [1, 1], failedIDs: nil, results: [row]).outcome(for: 1) == nil)
    #expect(AccountBulkReply(success: 1, failed: 0, successIDs: [1], failedIDs: nil, results: [row]).outcome(for: 1) == true)
    let failedRow = AccountBulkReply.Item(accountID: 2, success: false)
    #expect(AccountBulkReply(success: 0, failed: 1, successIDs: nil, failedIDs: [2], results: [failedRow]).outcome(for: 2) == false)
    #expect(AccountBulkReply(success: 0, failed: 1, successIDs: [2], failedIDs: [2], results: [failedRow]).outcome(for: 2) == nil)
    #expect(AccountBulkReply(success: 0, failed: 1, successIDs: nil, failedIDs: nil, results: [failedRow]).outcome(for: 2) == false)
    #expect(AccountBulkReply(success: 2, failed: 0, successIDs: nil, failedIDs: nil, results: [row, row]).outcome(for: 1) == nil)
}
