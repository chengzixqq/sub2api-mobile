import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

private let plaintextKey = "sk-plaintext-never-decode-0123456789"
private let requestLogJSON = #"{"id":41,"request_id":"req-41","created_at":"2026-10-16T08:00:00Z","model":"gpt-example","upstream_model":"upstream-example","user_id":8,"account_id":9,"api_key_id":10,"group_id":3,"input_tokens":12,"output_tokens":4,"cache_creation_tokens":3,"cache_read_tokens":2,"actual_cost":"0.1234567890123456789","total_cost":"0.50","account_stats_cost":"0.1234567890123456789","account_rate_multiplier":"0.3","account_cost":"0.12","provider_cost_recorded":true,"duration_ms":1250,"first_token_ms":null,"user":{"id":8,"email":"demo@example.invalid","username":"演示用户","password":"never-decode"},"api_key":{"id":10,"name":"演示 Key","key":"sk-plaintext-never-decode-0123456789","key_masked":"sk-…6789"},"account":{"name":"账号 A","credentials":{"token":"never-decode"}},"group":{"name":"分组 A"}}"#
private let requestErrorJSON = #"{"id":51,"created_at":"2026-10-16T08:01:00Z","request_id":"req-51","phase":"upstream","type":"upstream_error","error_owner":"provider","error_source":"upstream_http","severity":"P2","status_code":429,"platform":"openai","model":"gpt-example","resolved":true,"resolved_at":"2026-10-16T09:00:00Z","resolved_by_user_name":"值班","client_request_id":"client-51","message":"rate limited Authorization: Bearer super-secret-token","user_id":8,"user_email":"demo@example.invalid","api_key_id":10,"api_key_name":"演示 Key","account_id":9,"group_id":3,"stream":true,"request_type":2,"duration_ms":2300,"error_body":"never-decode-raw-body","upstream_error_detail":"never-decode-raw-upstream","api_key_prefix":"never-decode-key","client_ip":"203.0.113.9","user_agent":"never-decode-agent","upstream_status_code":429,"upstream_latency_ms":900,"response_latency_ms":920,"time_to_first_token_ms":null}"#
private let oldErrorJSON = #"{"id":52,"created_at":"2026-10-16T08:02:00Z","request_id":"req-52","phase":"upstream","type":"upstream_error","error_owner":"","error_source":"","severity":"","status_code":200,"platform":"openai","model":"","requested_model":"gpt-example","resolved":false,"resolved_at":null,"resolved_by_user_name":"","client_request_id":"","message":"Recovered upstream error 429: slow down","user_id":null,"user_email":"","api_key_id":null,"account_id":9,"account_name":"","group_name":"","request_type":null,"duration_ms":null}"#
private let usagePageJSON = "{\"items\":[\(requestLogJSON)],\"total\":null,\"pages\":null,\"page\":1,\"page_size\":100,\"has_more\":false,\"total_exact\":false}"
private let errorPageJSON = "{\"items\":[\(requestErrorJSON)],\"total\":7,\"page\":1,\"page_size\":100,\"pages\":1,\"has_more\":false,\"total_exact\":true}"

private let dayEnd = Date(timeIntervalSince1970: 1_792_137_600)
private let lastDay = LogTimeWindow.range(dayEnd.addingTimeInterval(-86_400), dayEnd)
/// Not the phone's zone on the test machines, so a device-zone leak shows.
private let siteZone = ServerTimeZone(identifier: "Asia/Kathmandu", utcOffset: "+05:45")!

private func usageRow(_ fields: String) -> String {
    #"{"id":1,"request_id":"old","created_at":"2026-10-16T00:00:00Z","model":"m","user_id":1,"account_id":1,"api_key_id":1,"actual_cost":0.75"# + fields + "}"
}
private func values(_ items: [URLQueryItem]) -> [String: String] {
    Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}
private func sent(_ request: URLRequest) -> [String: String] {
    guard let url = request.url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
    return values(items)
}
private func logClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture"), transport: transport, requestClock: .immediate, serverTimeZone: siteZone)
}

// MARK: Envelopes (Page, 00 §9.4)

@Test func usageDeferredPageDecodesIntoPage() throws {
    let data = Data("{\"items\":[\(requestLogJSON)],\"total\":null,\"pages\":null,\"page\":2,\"page_size\":100,\"has_more\":true,\"total_exact\":false}".utf8)
    let page = try JSONDecoder().decode(Page<UsageRequestRecord>.self, from: data)
    #expect(page.total == nil && page.pages == nil && page.hasMore && page.page == 2)
    #expect(page.items.first?.id == 41)
    let end = try JSONDecoder().decode(Page<UsageRequestRecord>.self, from: Data(#"{"items":[],"total":null,"pages":null,"page":3,"page_size":100,"has_more":false,"total_exact":false}"#.utf8))
    #expect(!end.hasMore && end.total == nil)
    let bare = try JSONDecoder().decode(Page<UsageRequestRecord>.self, from: Data(#"{"items":[],"total":null,"page":1,"page_size":100}"#.utf8))
    #expect(!bare.hasMore)
}

@Test func incrementalEnvelopeCarriesSinceAndLatestID() throws {
    let data = Data("{\"items\":[\(requestLogJSON)],\"total\":null,\"pages\":null,\"page\":1,\"page_size\":100,\"has_more\":true,\"since_id\":40,\"latest_id\":57}".utf8)
    let page = try JSONDecoder().decode(Page<UsageRequestRecord>.self, from: data)
    #expect(page.sinceID == 40 && page.latestID == 57 && page.hasMore)
}

@Test func upstreamErrorPageWithoutHasMoreFollowsPages() throws {
    func page(_ number: Int, pages: Int, total: Int) throws -> Page<RequestErrorRecord> {
        try JSONDecoder().decode(Page<RequestErrorRecord>.self, from: Data("{\"items\":[],\"total\":\(total),\"page\":\(number),\"page_size\":100,\"pages\":\(pages)}".utf8))
    }
    #expect(try page(2, pages: 3, total: 250).hasMore)
    #expect(try !page(3, pages: 3, total: 250).hasMore)
    #expect(try !page(1, pages: 1, total: 0).hasMore)
}

// MARK: Usage records (40 §6.2, D05)

@Test func accountCostPrefersServerValue() throws {
    let record = try JSONDecoder().decode(UsageRequestRecord.self, from: Data(requestLogJSON.utf8))
    #expect(record.accountCost == Decimal(string: "0.12") && record.providerCostRecorded == true)
    #expect(record.actualCost == Decimal(string: "0.1234567890123456789") && record.standardCost == Decimal(string: "0.50"))
    let unrecorded = requestLogJSON.replacingOccurrences(of: #""account_cost":"0.12","provider_cost_recorded":true"#, with: #""account_cost":0,"provider_cost_recorded":false"#)
    let zero = try JSONDecoder().decode(UsageRequestRecord.self, from: Data(unrecorded.utf8))
    #expect(zero.accountCost == 0 && zero.providerCostRecorded == false)
}

@Test func accountCostFormulaOnlyWhenKeyMissing() throws {
    func cost(_ fields: String) throws -> Decimal? {
        try JSONDecoder().decode(UsageRequestRecord.self, from: Data(usageRow(fields).utf8)).accountCost
    }
    let snapshot = #","total_cost":"0.50","account_stats_cost":"0.40","account_rate_multiplier":"0.30""#
    #expect(try cost(snapshot + #","provider_cost_recorded":true"#) == Decimal(string: "0.12"))
    #expect(try cost(snapshot + #","account_cost":null,"provider_cost_recorded":true"#) == Decimal(string: "0.12"))
    #expect(try cost(snapshot + #","provider_cost_recorded":false"#) == 0)
    #expect(try cost(#","total_cost":"0.50""#) == Decimal(string: "0.50"))
    #expect(try cost("") == nil)
    let old = try JSONDecoder().decode(UsageRequestRecord.self, from: Data(usageRow("").utf8))
    #expect(old.providerCostRecorded == nil && old.standardCost == nil && old.actualCost == Decimal(string: "0.75"))
}

@Test func usageRecordReadsLabelsAndNeverHoldsPlaintextKey() throws {
    let record = try JSONDecoder().decode(UsageRequestRecord.self, from: Data(requestLogJSON.utf8))
    #expect(record.userEmail == "demo@example.invalid" && record.userName == "演示用户")
    #expect(record.apiKeyName == "演示 Key" && record.apiKeyMasked == "sk-…6789")
    #expect(record.accountName == "账号 A" && record.groupName == "分组 A")
    #expect(record.totalTokens == 21 && record.durationMs == 1250 && record.firstTokenMs == nil)
    let dump = String(reflecting: record) + Mirror(reflecting: record).children.map { String(reflecting: $0.value) }.joined()
    for secret in [plaintextKey, "never-decode"] { #expect(!dump.contains(secret)) }
    let blank = usageRow(#","user":{"email":"","username":""},"api_key":{"name":"","key":"sk-plaintext-never-decode-0123456789","key_masked":""}"#)
    let empty = try JSONDecoder().decode(UsageRequestRecord.self, from: Data(blank.utf8))
    #expect(empty.userEmail == nil && empty.userName == nil && empty.apiKeyName == nil && empty.apiKeyMasked == nil)
    #expect(!String(reflecting: empty).contains(plaintextKey))
}

// MARK: Error records (40 §6.2, D04)

@Test func errorRecordDecodesD04FieldsAndOldRowsAsNil() throws {
    let record = try JSONDecoder().decode(RequestErrorRecord.self, from: Data(requestErrorJSON.utf8))
    #expect(record.durationMs == 2300 && record.errorOwner == "provider" && record.errorSource == "upstream_http" && record.severity == "P2")
    #expect(record.clientRequestID == "client-51" && record.userEmail == "demo@example.invalid" && record.apiKeyID == 10 && record.apiKeyName == "演示 Key")
    #expect(record.stream == true && record.requestType == 2 && record.resolvedByUserName == "值班")
    #expect(record.resolvedAt == ISO8601DateFormatter().date(from: "2026-10-16T09:00:00Z"))
    #expect(record.message.contains("rate limited") && !record.message.contains("super-secret"))
    let old = try JSONDecoder().decode(RequestErrorRecord.self, from: Data(oldErrorJSON.utf8))
    #expect(old.durationMs == nil && old.errorOwner == nil && old.errorSource == nil && old.severity == nil && old.clientRequestID == nil)
    #expect(old.userEmail == nil && old.apiKeyID == nil && old.apiKeyName == nil && old.stream == nil && old.requestType == nil)
    #expect(old.resolvedAt == nil && old.resolvedByUserName == nil && old.accountName == nil && old.groupName == nil)
    #expect(old.model == "gpt-example" && old.userID == nil)
}

@Test func errorRecordDropsRawBodiesAndCredentials() throws {
    let record = try JSONDecoder().decode(RequestErrorRecord.self, from: Data(requestErrorJSON.utf8))
    #expect(record.upstreamStatusCode == 429 && record.upstreamLatencyMs == 900 && record.firstTokenMs == nil)
    let dump = String(reflecting: record)
    for raw in ["never-decode", "203.0.113.9", "super-secret"] { #expect(!dump.contains(raw)) }
    let scrubbed = RequestLogPresentation.safeMessage(#"{"access_token":"sensitive-access","password":"sensitive-password"} sk-123456789abc Bearer sensitive-bearer"#)
    #expect(!scrubbed.contains("sensitive-") && !scrubbed.contains("123456789abc"))
    #expect(scrubbed.contains("已隐藏凭据"))
    for value in ["Authorization: Basic c2VjcmV0", "https://user:secret-password@example.invalid/path", "Cookie: session=secret-cookie; theme=dark", "https://host.invalid/path?access_token=secret-query&x=1", "session_id=secret-session", "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.secret-signature"] {
        let safe = RequestLogPresentation.safeMessage(value)
        #expect(!safe.contains("secret-") && !safe.contains("c2VjcmV0") && !safe.contains("eyJhbGci"))
    }
}

@Test func upstreamStatusCoversCodeAccountAuthAndUnknown() throws {
    func status(_ code: Int, phase: String = "upstream", message: String) throws -> UpstreamErrorStatus {
        let json = #"{"id":1,"created_at":"2026-10-16T08:00:00Z","request_id":"r","phase":"PHASE","type":"upstream_error","status_code":CODE,"platform":"openai","model":"m","resolved":false,"message":"MESSAGE"}"#
            .replacingOccurrences(of: "PHASE", with: phase).replacingOccurrences(of: "CODE", with: String(code))
            .replacingOccurrences(of: "MESSAGE", with: message)
        return try JSONDecoder().decode(RequestErrorRecord.self, from: Data(json.utf8)).upstreamStatus
    }
    #expect(try status(502, message: "Recovered upstream error 429") == .code(502))
    #expect(try status(200, message: "Recovered upstream error 429: slow down") == .code(429))
    #expect(try status(200, message: "Recovered upstream error 529") == .code(529))
    #expect(try status(200, phase: "account_auth", message: "Recovered account authentication failure") == .accountAuth)
    #expect(try status(200, phase: "account_auth", message: "Recovered upstream error 401") == .code(401))
    #expect(try status(200, message: "Recovered upstream error") == .unknown)
    #expect(try status(200, message: "Recovered upstream error 50213") == .unknown)
    #expect(try status(200, message: "upstream said Recovered upstream error 429") == .unknown)
}

@Test func usageRequestTypeCodesAndTitles() {
    #expect(UsageRequestType.allCases.map(\.rawValue) == ["stream", "sync", "ws_v2", "cyber", "live"])
    #expect((1...5).map { UsageRequestType(code: Int16($0)) } == [.sync, .stream, .wsV2, .cyber, .live])
    for code: Int16 in [0, 6, -1] { #expect(UsageRequestType(code: code) == nil) }
    #expect(UsageRequestType(rawValue: "unknown") == nil)
    #expect(UsageRequestType.allCases.map(\.title) == ["流式", "同步", "WS", "安全策略", "Live"])
    #expect(UsageRequestType.allCases.map(\.detailTitle) == ["流式", "非流式", "WebSocket", "安全策略", "Live"])
}

// MARK: Query items (40 §6.7)

@Test func usageQueryUsesPageSizeSiteTimeZoneAndDeferredCount() throws {
    var filter = RequestLogFilter(time: lastDay, accountID: 9, groupID: 3, userID: 8, model: "  model/a+b  ", requestID: "req +/&=")
    filter.apiKeyID = 10; filter.requestType = "ws_v2"
    let first = values(try filter.queryItems(page: 2, errors: false, timeZone: siteZone))
    #expect(first["page"] == "2" && first["page_size"] == "100" && first["count_mode"] == "deferred" && first["sort_order"] == "desc")
    #expect(first["timezone"] == "Asia/Kathmandu")
    #expect(first["account_id"] == "9" && first["group_id"] == "3" && first["user_id"] == "8" && first["api_key_id"] == "10")
    #expect(first["model"] == "model/a+b" && first["request_id"] == "req +/&=" && first["request_type"] == "ws_v2")
    #expect(first["start_time"]?.hasSuffix("Z") == true && first["end_time"]?.hasSuffix("Z") == true)
    #expect(first["key_view"] == nil && first["time_range"] == nil && first["view"] == nil)
    let second = values(try filter.queryItems(page: 3, errors: false, timeZone: siteZone))
    #expect(first["start_time"] == second["start_time"] && first["end_time"] == second["end_time"])
    filter.pageSize = 5
    #expect(values(try filter.queryItems(page: 1, errors: false, timeZone: siteZone))["page_size"] == "5")
}

@Test func modelSourceOnlyForUsageWithModel() throws {
    var filter = RequestLogFilter(time: lastDay, model: "claude-x", modelSource: .upstream)
    #expect(values(try filter.queryItems(page: 1, errors: false, timeZone: siteZone))["model_source"] == "upstream")
    let errors = values(try filter.queryItems(page: 1, errors: true, timeZone: siteZone))
    #expect(errors["model"] == "claude-x" && errors["model_source"] == nil && errors["view"] == "all")
    #expect(errors["timezone"] == nil && errors["count_mode"] == nil && errors["key_view"] == nil)
    filter.model = "   "
    #expect(values(try filter.queryItems(page: 1, errors: false, timeZone: siteZone))["model_source"] == nil)
    filter.model = nil
    #expect(values(try filter.queryItems(page: 1, errors: false, timeZone: siteZone))["model_source"] == nil)
}

@Test func rollingWindowOnlyEmitsTimeRangeForOps() throws {
    #expect(RollingWindow.allCases.map(\.rawValue) == ["5m", "30m", "1h", "6h", "24h", "7d", "30d"])
    for window in RollingWindow.allCases {
        let query = values(try RequestLogFilter(time: .rolling(window), groupID: 3).queryItems(page: 1, errors: true, timeZone: siteZone))
        #expect(query["time_range"] == window.rawValue && query["group_id"] == "3")
        #expect(query["start_time"] == nil && query["end_time"] == nil && query["timezone"] == nil && query["count_mode"] == nil)
    }
}

@Test func timeWindowRejectionsHappenBeforeSending() throws {
    func rejects(_ filter: RequestLogFilter, page: Int = 1, errors: Bool) -> Bool {
        do { _ = try filter.queryItems(page: page, errors: errors, timeZone: siteZone); return false }
        catch { return (error as? APIError)?.kind == .validation }
    }
    #expect(rejects(RequestLogFilter(time: .none), errors: true))
    #expect(rejects(RequestLogFilter(time: .none, requestID: "req-1"), errors: true))
    #expect(rejects(RequestLogFilter(time: .rolling(.h24)), errors: false))
    #expect(rejects(RequestLogFilter(time: .none), errors: false))
    #expect(rejects(RequestLogFilter(time: .none, requestID: "   "), errors: false))
    #expect(rejects(RequestLogFilter(time: .range(dayEnd, dayEnd.addingTimeInterval(-86_400))), errors: false))
    #expect(rejects(RequestLogFilter(time: .range(dayEnd, dayEnd)), errors: true))
    #expect(rejects(RequestLogFilter(time: .range(dayEnd.addingTimeInterval(-LogTimeWindow.maximumRange - 1), dayEnd)), errors: false))
    #expect(!rejects(RequestLogFilter(time: .range(dayEnd.addingTimeInterval(-LogTimeWindow.maximumRange), dayEnd)), errors: false))
    #expect(rejects(RequestLogFilter(time: lastDay), page: 0, errors: false))
    #expect(rejects(RequestLogFilter(time: lastDay, pageSize: 0), errors: false))
    #expect(rejects(RequestLogFilter(time: lastDay, pageSize: 1_001), errors: true))
    #expect(rejects(RequestLogFilter(time: lastDay, accountID: 0), errors: false))
    #expect(rejects(RequestLogFilter(time: lastDay, userID: -1), errors: true))
    var status = RequestLogFilter(time: lastDay); status.statusCode = 999
    #expect(rejects(status, errors: true))
    let byID = values(try RequestLogFilter(time: .none, requestID: " client:abc ", pageSize: 1).queryItems(page: 1, errors: false, timeZone: siteZone))
    #expect(byID["request_id"] == "client:abc" && byID["page_size"] == "1")
    #expect(byID["start_time"] == nil && byID["end_time"] == nil && byID["time_range"] == nil)
}

@Test func upstreamErrorsAcceptIdentityFiltersSinceD03() throws {
    var filter = RequestLogFilter(time: lastDay, accountID: 9, groupID: 3, userID: 8, model: "gpt-example", modelSource: .requested, requestID: "req-51")
    filter.apiKeyID = 10; filter.category = "rate_limit"; filter.statusCode = 429; filter.requestType = "stream"
    let query = values(try filter.queryItems(page: 1, errors: true, timeZone: siteZone))
    #expect(query["user_id"] == "8" && query["model"] == "gpt-example" && query["request_id"] == "req-51" && query["api_key_id"] == "10")
    #expect(query["status_codes"] == "429" && query["category"] == "rate_limit" && query["view"] == "all" && query["request_type"] == nil)
    let legacy = filter.upstreamErrorFilter()
    #expect(legacy.userID == nil && legacy.apiKeyID == nil && legacy.model == nil && legacy.modelSource == nil && legacy.requestID == nil)
    #expect(legacy.category.isEmpty && legacy.requestType.isEmpty && legacy.time == lastDay)
    let old = values(try legacy.queryItems(page: 1, errors: true, timeZone: siteZone))
    #expect(old["account_id"] == "9" && old["group_id"] == "3" && old["status_codes"] == "429" && old["start_time"] == query["start_time"])
    #expect(old["user_id"] == nil && old["api_key_id"] == nil && old["model"] == nil && old["request_id"] == nil && old["category"] == nil)
}

@Test func incrementalQueryKeepsOnlyObjectFiltersSinceIDAndPageSize() throws {
    let filter = RequestLogFilter(time: lastDay, accountID: 9, model: "gpt-example", modelSource: .mapping, pageSize: 20)
    let usage = try filter.incrementalQueryItems(sinceID: 40, errors: false, timeZone: siteZone)
    #expect(Set(usage.map(\.name)) == ["account_id", "model", "model_source", "timezone", "since_id", "page_size"])
    #expect(values(usage)["since_id"] == "40" && values(usage)["page_size"] == "100" && values(usage)["timezone"] == "Asia/Kathmandu")
    let errors = try RequestLogFilter(time: .rolling(.h1), groupID: 3).incrementalQueryItems(sinceID: 0, errors: true, timeZone: siteZone)
    #expect(Set(errors.map(\.name)) == ["group_id", "view", "since_id", "page_size"])
    #expect(throws: APIError.self) { try filter.incrementalQueryItems(sinceID: -1, errors: false, timeZone: siteZone) }
}

// MARK: APIClient (R19: the only log, count and user-search methods)

@Test func logAPIUsesBackendRoutesPageSizeAndSiteZone() async throws {
    let transport = ScriptedTransport { request in
        let path = request.url!.path
        return okReply(path.hasSuffix("/51") ? requestErrorJSON : path.contains("ops/") ? errorPageJSON : usagePageJSON)
    }
    let client = logClient(transport)
    let filter = RequestLogFilter(time: lastDay, accountID: 9)
    let records = try await client.requestRecords(page: 1, filter: filter, maskedView: false)
    let errors = try await client.errorRecords(page: 1, filter: filter, kind: .request)
    let upstream = try await client.errorRecords(page: 1, filter: filter, kind: .upstream)
    let detail = try await client.errorRecord(id: 51, kind: .upstream)
    #expect(records.items.first?.id == 41 && records.total == nil && errors.total == 7 && !upstream.hasMore && detail.statusCode == 429)
    #expect(ErrorLogKind.request.opsPath == "admin/ops/request-errors" && ErrorLogKind.upstream.opsPath == "admin/ops/upstream-errors")
    let requests = await transport.requests
    #expect(requests.map { $0.url!.path } == ["/api/v1/admin/usage", "/api/v1/admin/ops/request-errors", "/api/v1/admin/ops/upstream-errors", "/api/v1/admin/ops/upstream-errors/51"])
    #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil && $0.timeoutInterval == RequestTimeout.read })
    let usage = sent(requests[0])
    #expect(usage["timezone"] == "Asia/Kathmandu" && usage["page_size"] == "100" && usage["account_id"] == "9")
    #expect(sent(requests[1])["view"] == "all" && sent(requests[1])["timezone"] == nil)
}

@Test func usageListSendsKeyViewOnlyWhenMasked() async throws {
    let transport = ScriptedTransport { request in okReply(request.url!.path.contains("ops/") ? errorPageJSON : usagePageJSON) }
    let client = logClient(transport)
    let filter = RequestLogFilter(time: lastDay)
    _ = try await client.requestRecords(page: 1, filter: filter, maskedView: true)
    _ = try await client.requestRecords(sinceID: 40, filter: filter, maskedView: true)
    _ = try await client.requestRecords(page: 1, filter: filter, maskedView: false)
    _ = try await client.requestRecords(sinceID: 40, filter: filter, maskedView: false)
    _ = try await client.errorRecords(page: 1, filter: filter, kind: .request)
    _ = try await client.errorRecords(sinceID: 40, filter: filter)
    _ = try await client.errorCount(filter: filter, kind: .upstream)
    let keyViews = await transport.requests.map { sent($0)["key_view"] }
    #expect(keyViews == ["masked", "masked", nil, nil, nil, nil, nil])
    for errors in [false, true] {
        #expect(values(try filter.queryItems(page: 1, errors: errors, timeZone: siteZone))["key_view"] == nil)
        #expect(values(try filter.incrementalQueryItems(sinceID: 1, errors: errors, timeZone: siteZone))["key_view"] == nil)
    }
}

@Test func incrementalReadsUseSinceIDWithoutPageOrTime() async throws {
    let transport = ScriptedTransport { request in
        okReply(request.url!.path.contains("ops/")
            ? #"{"items":[],"total":null,"page":1,"page_size":100,"pages":null,"has_more":false,"since_id":40,"latest_id":40}"#
            : "{\"items\":[\(requestLogJSON)],\"total\":null,\"page\":1,\"page_size\":100,\"has_more\":false,\"since_id\":40,\"latest_id\":41}")
    }
    let client = logClient(transport)
    let usage = try await client.requestRecords(sinceID: 40, filter: RequestLogFilter(time: lastDay, accountID: 9), maskedView: false)
    let errors = try await client.errorRecords(sinceID: 40, filter: RequestLogFilter(time: .rolling(.h1), groupID: 3))
    #expect(usage.latestID == 41 && usage.items.first?.id == 41 && errors.latestID == 40)
    let requests = await transport.requests
    #expect(requests.map { $0.url!.path } == ["/api/v1/admin/usage", "/api/v1/admin/ops/request-errors"])
    for request in requests {
        let query = sent(request)
        #expect(query["since_id"] == "40" && query["page_size"] == "100")
        for key in ["page", "start_time", "end_time", "time_range", "sort_by", "sort_order", "count_mode"] { #expect(query[key] == nil) }
    }
}

@Test func errorCountForcesFirstPageSizeOneAndReadsTotal() async throws {
    let transport = ScriptedTransport { request in
        if request.url!.path.contains("upstream") { return okReply(#"{"items":[],"total":12,"page":1,"page_size":1,"pages":12}"#) }
        return okReply("{\"items\":[\(requestErrorJSON)],\"total\":7,\"page\":1,\"page_size\":1,\"pages\":7,\"has_more\":true}")
    }
    let client = logClient(transport)
    let filter = RequestLogFilter(time: .rolling(.h24), groupID: 3, pageSize: 100)
    #expect(try await client.errorCount(filter: filter, kind: .request) == 7)
    #expect(try await client.errorCount(filter: filter, kind: .upstream) == 12)
    let requests = await transport.requests
    #expect(requests.map { $0.url!.path } == ["/api/v1/admin/ops/request-errors", "/api/v1/admin/ops/upstream-errors"])
    for request in requests {
        let query = sent(request)
        #expect(query["page"] == "1" && query["page_size"] == "1" && query["time_range"] == "24h" && query["group_id"] == "3")
        #expect(query["view"] == "all" && query["key_view"] == nil)
    }
    let missing = logClient(ScriptedTransport { _ in okReply(#"{"items":[],"total":null,"page":1,"page_size":1,"has_more":false}"#) })
    await #expect(throws: APIError.self) { try await missing.errorCount(filter: filter, kind: .request) }
    let disabled = logClient(ScriptedTransport { _ in errorReply(404, reason: "OPS_DISABLED") })
    let error = await thrownAPIError { _ = try await disabled.errorCount(filter: filter, kind: .request) }
    #expect(error?.reason == "OPS_DISABLED")
    let none = logClient(ScriptedTransport { _ in okReply("{}") })
    let rejected = await thrownAPIError { _ = try await none.errorCount(filter: RequestLogFilter(time: .none), kind: .request) }
    #expect(rejected?.kind == .validation)
}

@Test func searchUsageUsersDecodesAndSkipsBlankKeyword() async throws {
    let transport = ScriptedTransport { _ in okReply(#"[{"id":8,"email":"a+b@example.invalid","deleted":true},{"id":9,"email":"c@example.invalid"}]"#) }
    let client = logClient(transport)
    #expect(try await client.searchUsageUsers("  \n ").isEmpty)
    #expect(await transport.requests.isEmpty)
    let users = try await client.searchUsageUsers("  a+b ")
    #expect(users == [UsageUserMatch(id: 8, email: "a+b@example.invalid", deleted: true), UsageUserMatch(id: 9, email: "c@example.invalid", deleted: false)])
    let requests = await transport.requests
    let request = try #require(requests.first)
    #expect(requests.count == 1 && request.url?.path == "/api/v1/admin/usage/search-users")
    #expect(sent(request) == ["q": "a+b"])
    #expect(request.url?.absoluteString.contains("q=a%2Bb") == true)
    #expect(request.httpMethod == "GET" && request.timeoutInterval == RequestTimeout.read)
}

private actor LateRequestLogTransport: HTTPTransport {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func data(for request: URLRequest) async throws -> HTTPResponse {
        started = true; startWaiter?.resume(); startWaiter = nil
        // Deliberately ignores cancellation, like a late response from a transport.
        await withCheckedContinuation { releaseWaiter = $0 }
        return HTTPResponse(statusCode: 200, data: Data(#"{"code":0,"data":{"items":[],"total":null,"page":1,"page_size":100,"has_more":false,"total_exact":false}}"#.utf8))
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
    let read = Task { try await client.requestRecords(page: 1, filter: RequestLogFilter(time: lastDay), maskedView: false) }
    await transport.waitUntilStarted()
    await client.cancelAll()
    await transport.release()
    do { _ = try await read.value; Issue.record("A late old-session log response was accepted.") }
    catch { #expect(error is CancellationError) }
}
