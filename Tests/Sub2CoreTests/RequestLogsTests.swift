import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let requestLogJSON = #"{"id":41,"request_id":"req-41","created_at":"2026-10-16T08:00:00Z","model":"gpt-example","upstream_model":"upstream-example","user_id":8,"account_id":9,"api_key_id":10,"group_id":3,"input_tokens":12,"output_tokens":4,"cache_creation_tokens":3,"cache_read_tokens":2,"actual_cost":"0.1234567890123456789","total_cost":"0.50","account_stats_cost":"0.1234567890123456789","account_rate_multiplier":"0.3","duration_ms":1250,"first_token_ms":null,"user":{"email":"demo@example.invalid","password":"never-decode"},"api_key":{"key":"never-decode"},"account":{"name":"账号 A","credentials":{"token":"never-decode"}},"group":{"name":"分组 A"}}"#
private let requestErrorJSON = #"{"id":51,"created_at":"2026-10-16T08:01:00Z","request_id":"req-51","phase":"upstream","type":"upstream_error","status_code":429,"platform":"openai","model":"gpt-example","resolved":false,"message":"rate limited Authorization: Bearer super-secret-token","user_id":8,"account_id":9,"group_id":3,"error_body":"never-decode-raw-body","upstream_error_detail":"never-decode-raw-upstream","api_key_prefix":"never-decode-key","upstream_status_code":429,"upstream_latency_ms":900,"response_latency_ms":920,"time_to_first_token_ms":null}"#

@Test func requestLogDeferredPaginationUsesHasMoreAndDoesNotInventTotals() throws {
    let data = Data("{\"items\":[\(requestLogJSON)],\"total\":null,\"pages\":null,\"page\":2,\"page_size\":30,\"has_more\":true,\"total_exact\":false}".utf8)
    let page = try JSONDecoder().decode(RequestLogPage<UsageRequestRecord>.self, from: data)
    #expect(page.total == nil && !page.totalExact && page.hasMore && page.page == 2)
    #expect(page.items.first?.id == 41)
    let end = try JSONDecoder().decode(RequestLogPage<UsageRequestRecord>.self, from: Data(#"{"items":[],"total":null,"pages":null,"page":3,"page_size":30,"has_more":false,"total_exact":false}"#.utf8))
    #expect(!end.hasMore && end.total == nil)
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(RequestLogPage<UsageRequestRecord>.self, from: Data(#"{"items":[],"total":null,"page":1,"page_size":30}"#.utf8))
    }
}

@Test func requestLogBillingKeepsDecimalSnapshotsAndDefaultFormulaSeparateFromCharge() throws {
    let record = try JSONDecoder().decode(UsageRequestRecord.self, from: Data(requestLogJSON.utf8))
    #expect(record.actualCost == Decimal(string: "0.1234567890123456789"))
    #expect(record.accountCost == Decimal(string: "0.03703703670370370367"))
    #expect(record.totalTokens == 21 && record.durationMs == 1250 && record.firstTokenMs == nil)
    #expect(record.userEmail == "demo@example.invalid" && record.accountName == "账号 A" && record.groupName == "分组 A")
    // Build a minimal historical record without custom price or account multiplier.
    let minimal = #"{"id":1,"request_id":"old","created_at":"2026-10-16T00:00:00Z","model":"m","user_id":1,"account_id":1,"api_key_id":1,"total_cost":"0.50","actual_cost":0.75}"#
    let old = try JSONDecoder().decode(UsageRequestRecord.self, from: Data(minimal.utf8))
    #expect(old.accountCost == Decimal(string: "0.50") && old.actualCost == Decimal(string: "0.75"))
    let missing = minimal.replacingOccurrences(of: ",\"total_cost\":\"0.50\"", with: "")
    let unknown = try JSONDecoder().decode(UsageRequestRecord.self, from: Data(missing.utf8))
    #expect(unknown.standardCost == nil && unknown.accountCost == nil && unknown.actualCost == Decimal(string: "0.75"))
}

@Test func requestLogFiltersPreserveLiteralIDsModelAndStableTimeBoundaries() throws {
    let end = Date(timeIntervalSince1970: 1_792_137_600)
    var filter = RequestLogFilter(start: end.addingTimeInterval(-86_400), end: end, accountID: 9, groupID: 3)
    filter.userID = 8; filter.apiKeyID = 10; filter.model = "  model/a+b  "; filter.requestID = "req +/&="; filter.requestType = "ws_v2"
    let values = Dictionary(uniqueKeysWithValues: try filter.queryItems(page: 2).map { ($0.name, $0.value ?? "") })
    #expect(values["count_mode"] == "deferred" && values["sort_order"] == "desc" && values["page"] == "2")
    #expect(values["account_id"] == "9" && values["group_id"] == "3" && values["user_id"] == "8" && values["api_key_id"] == "10")
    #expect(values["model"] == "model/a+b" && values["request_id"] == "req +/&=" && values["request_type"] == "ws_v2")
    let secondPage = Dictionary(uniqueKeysWithValues: try filter.queryItems(page: 3).map { ($0.name, $0.value ?? "") })
    #expect(values["start_time"] == secondPage["start_time"] && values["end_time"] == secondPage["end_time"])
    filter.category = "rate_limit"; filter.resolved = false; filter.statusCode = 429
    let errors = Dictionary(uniqueKeysWithValues: try filter.queryItems(page: 1, errors: true).map { ($0.name, $0.value ?? "") })
    #expect(errors["status_codes"] == "429" && errors["category"] == "rate_limit" && errors["resolved"] == "false")
    #expect(errors["count_mode"] == nil && errors["request_type"] == nil)
    #expect(throws: APIError.self) { try filter.queryItems(page: 1, errors: true, errorKind: .upstream) }
    let upstream = Dictionary(uniqueKeysWithValues: try filter.upstreamErrorFilter().queryItems(page: 1, errors: true, errorKind: .upstream).map { ($0.name, $0.value ?? "") })
    #expect(upstream["account_id"] == "9" && upstream["group_id"] == "3" && upstream["status_codes"] == "429")
    #expect(upstream["user_id"] == nil && upstream["api_key_id"] == nil && upstream["model"] == nil && upstream["request_id"] == nil && upstream["category"] == nil)
}

@Test func requestLogValidationRejectsInvalidRangeIDsAndPageBeforeSending() throws {
    var filter = RequestLogFilter(start: Date(timeIntervalSince1970: 2), end: Date(timeIntervalSince1970: 1))
    #expect(throws: APIError.self) { try filter.queryItems(page: 1) }
    filter = RequestLogFilter(); filter.accountID = -1
    #expect(throws: APIError.self) { try filter.queryItems(page: 1) }
    filter.accountID = nil
    #expect(throws: APIError.self) { try filter.queryItems(page: 0) }
    filter.statusCode = 999
    #expect(throws: APIError.self) { try filter.queryItems(page: 1, errors: true) }
}

@Test func requestErrorDetailsRetainSafeReasonAndDropRawBodiesAndCredentials() throws {
    let record = try JSONDecoder().decode(RequestErrorRecord.self, from: Data(requestErrorJSON.utf8))
    #expect(record.message.contains("rate limited") && !record.message.contains("super-secret"))
    #expect(record.upstreamStatusCode == 429 && record.upstreamLatencyMs == 900 && record.firstTokenMs == nil)
    let scrubbed = RequestLogPresentation.safeMessage(#"{"access_token":"sensitive-access","password":"sensitive-password"} sk-123456789abc Bearer sensitive-bearer"#)
    #expect(!scrubbed.contains("sensitive-") && !scrubbed.contains("123456789abc"))
    #expect(scrubbed.contains("已隐藏凭据"))
    for value in ["Authorization: Basic c2VjcmV0", "https://user:secret-password@example.invalid/path", "Cookie: session=secret-cookie; theme=dark", "https://host.invalid/path?access_token=secret-query&x=1", "session_id=secret-session", "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.secret-signature"] {
        let safe = RequestLogPresentation.safeMessage(value)
        #expect(!safe.contains("secret-") && !safe.contains("c2VjcmV0") && !safe.contains("eyJhbGci"))
    }
}

private actor RequestLogTransport: HTTPTransport {
    private var seen: [URLRequest] = []
    func data(for request: URLRequest) async throws -> HTTPResponse {
        seen.append(request)
        let path = request.url!.path
        let data: String
        if path.hasSuffix("/51") { data = requestErrorJSON }
        else if path.contains("ops/") { data = "{\"items\":[\(requestErrorJSON)],\"total\":1,\"page\":1,\"page_size\":30,\"pages\":1,\"has_more\":false,\"total_exact\":true}" }
        else { data = "{\"items\":[\(requestLogJSON)],\"total\":null,\"page\":1,\"page_size\":30,\"has_more\":true,\"total_exact\":false}" }
        return HTTPResponse(statusCode: 200, data: Data("{\"code\":0,\"data\":\(data)}".utf8))
    }
    func stream(for request: URLRequest) async throws -> HTTPStreamResponse { throw URLError(.unsupportedURL) }
    func requests() -> [URLRequest] { seen }
}

@Test func requestLogAPIUsesCurrentBackendRoutesAndNeverFetchesRawPayloads() async throws {
    let transport = RequestLogTransport()
    let server = ServerProfile(name: "日志测试", baseURL: URL(string: "https://logs.example.invalid")!, authentication: .adminKey)
    let client = APIClient(server: server, credential: .adminKey("fixture"), transport: transport)
    let filter = RequestLogFilter(accountID: 9)
    let records = try await client.requestRecords(page: 1, filter: filter)
    let errors = try await client.errorRecords(page: 1, filter: filter)
    let upstream = try await client.errorRecords(page: 1, filter: filter, kind: .upstream)
    let detail = try await client.errorRecord(id: 51, kind: .upstream)
    #expect(records.hasMore && errors.total == 1 && !upstream.hasMore && detail.statusCode == 429)
    let requests = await transport.requests()
    #expect(requests.map { $0.url!.path } == ["/api/v1/admin/usage", "/api/v1/admin/ops/request-errors", "/api/v1/admin/ops/upstream-errors", "/api/v1/admin/ops/upstream-errors/51"])
    #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
    #expect(requests[0].timeoutInterval == 45)
    #expect(throws: APIError.self) { try RequestLogFilter(accountID: 0).queryItems(page: 1) }
}

private actor LateRequestLogTransport: HTTPTransport {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func data(for request: URLRequest) async throws -> HTTPResponse {
        started = true; startWaiter?.resume(); startWaiter = nil
        // Deliberately ignores cancellation, like a late response from a transport.
        await withCheckedContinuation { releaseWaiter = $0 }
        return HTTPResponse(statusCode: 200, data: Data(#"{"code":0,"data":{"items":[],"total":null,"page":1,"page_size":30,"has_more":false,"total_exact":false}}"#.utf8))
    }
    func stream(for request: URLRequest) async throws -> HTTPStreamResponse { throw URLError(.unsupportedURL) }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}

@Test func requestLogsRejectLateResponseAfterStationSessionCancellation() async throws {
    let transport = LateRequestLogTransport()
    let server = ServerProfile(name: "旧站点", baseURL: URL(string: "https://old-logs.example.invalid")!, authentication: .adminKey)
    let client = APIClient(server: server, credential: .adminKey("fixture"), transport: transport)
    let read = Task { try await client.requestRecords(page: 1, filter: RequestLogFilter()) }
    await transport.waitUntilStarted()
    await client.cancelAll()
    await transport.release()
    do { _ = try await read.value; Issue.record("A late old-session log response was accepted.") }
    catch { #expect(error is CancellationError) }
}
