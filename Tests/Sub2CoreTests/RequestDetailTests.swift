import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// 40 §7.2–§7.4: the request-detail wire (S4-03) and the rules S4-08 / S4-08b draw with.

private let eventsJSON = #"[{"at_unix_ms":1792114865000,"started_at_unix_ms":1792114864600,"duration_ms":400,"account_id":9,"account_name":"账号 A","upstream_status_code":429,"kind":"http_error","dropped_earlier_attempts":2,"upstream_response_body":"never-decode-body","upstream_url":"https://upstream.example.invalid/v1/messages","message":"never-decode-message","detail":"never-decode-detail"},{"at_unix_ms":1792114866000,"account_id":9,"upstream_status_code":504,"kind":"failover"}]"#
private let clientRequestID = "8d3c2b1a-0000-4000-8000-000000000061"
private let attemptsJSON = #"{"request_id":"req-61","client_request_id":"8d3c2b1a-0000-4000-8000-000000000061","client_status_code":200,"attempts":[{"index":1,"source":"upstream_error","outcome":"failed","platform":"anthropic","account_id":9,"account_name":"账号 A","proxy_id":null,"proxy_name":"direct/no_proxy","upstream_status_code":429,"upstream_request_id":"","kind":"http_error","stage":"","message":"rate limited api_key=sk-never-leak-123456","started_at":null,"ended_at":"2026-10-16T01:41:05.123456789Z","duration_ms":null,"first_token_ms":null,"error_log_id":61,"usage_id":null},{"index":2,"source":"usage","outcome":"success","platform":"anthropic","account_id":12,"account_name":"账号 B","proxy_id":3,"proxy_name":"代理 3","upstream_status_code":200,"upstream_request_id":"up-req-2","kind":"","stage":"","message":"","started_at":"2026-10-16T09:41:05+08:00","ended_at":"2026-10-16T01:41:07Z","duration_ms":1800,"first_token_ms":600,"error_log_id":null,"usage_id":77},{"source":"carrier","outcome":"exploded","account_id":null}],"error_log_ids":[61],"dropped_earlier_attempts":0}"#
private let emptyChainJSON = #"{"request_id":"req-0","client_request_id":"","client_status_code":null,"attempts":null,"error_log_ids":null,"dropped_earlier_attempts":0}"#
private let siteZone = TimeZone(identifier: "Asia/Shanghai")!

private func quoted(_ text: String) -> String { String(decoding: try! JSONEncoder().encode(text), as: UTF8.self) }
private func decoded<T: Decodable>(_ type: T.Type, _ json: String) throws -> T { try JSONDecoder().decode(T.self, from: Data(json.utf8)) }
private func date(_ raw: String) -> Date { ServerTime.parseTimestamp(raw)! }
private func detailClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture"), transport: transport, requestClock: .immediate)
}
private func sentQuery(_ request: URLRequest?) -> [URLQueryItem] {
    request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
}

/// Keys in `fields` replace the defaults with the same name, so no fixture sends a key twice.
private func object(_ fixed: String, defaults: [(String, String)], fields: String) -> String {
    let kept = defaults.filter { !fields.contains("\"\($0.0)\"") }.map { ",\"\($0.0)\":\($0.1)" }.joined()
    return "{" + fixed + kept + fields + "}"
}
/// An error-log detail; `status` is the client's code.
private func errorJSON(status: Int = 504, events: String? = eventsJSON, fields: String = "") -> String {
    let fixed = #""id":61,"created_at":"2026-10-16T01:41:07Z","type":"upstream_error","platform":"anthropic","model":"claude-example","requested_model":"","upstream_model":"claude-upstream","user_id":8,"user_email":"demo@example.invalid","api_key_id":10,"api_key_name":"演示 Key","account_id":9,"account_name":"账号 A","group_id":3,"group_name":"分组 A","stream":false,"error_body":"never-decode-raw-body","upstream_error_detail":"never-decode-upstream-detail","upstream_latency_ms":3000,"response_latency_ms":158,"client_ip":"203.0.113.9","user_agent":"never-decode-agent","status_code":"# + String(status)
    let defaults = [("phase", #""upstream""#), ("error_owner", #""provider""#), ("severity", #""P1""#), ("message", #""upstream timeout token=never-leak-123""#),
                    ("upstream_status_code", "429"), ("upstream_error_message", #""slow down Authorization: Bearer never-leak-token""#),
                    ("is_business_limited", "false"), ("resolved", "true"), ("resolved_at", #""2026-10-16T01:52:30Z""#), ("resolved_by_user_name", #""值班""#),
                    ("request_type", "null"), ("client_request_id", quoted(clientRequestID)), ("request_id", #""req-61""#), ("duration_ms", "null"),
                    ("time_to_first_token_ms", "null"), ("auth_latency_ms", "12"), ("routing_latency_ms", "30"), ("api_key_prefix", #""sk-abcdefXYZ""#),
                    ("upstream_errors", events.map(quoted) ?? "null")]
    return object(fixed, defaults: defaults, fields: fields)
}
private func usageJSON(_ fields: String = "") -> String {
    let fixed = #""id":41,"created_at":"2026-10-16T01:41:07Z","model":"claude-example","user_id":8,"account_id":12,"api_key_id":10,"account":{"name":"账号 B"},"total_cost":"0.5""#
    let defaults = [("request_id", quoted("client:" + clientRequestID)), ("actual_cost", #""0.12345""#), ("account_cost", #""0.12""#),
                    ("provider_cost_recorded", "true"), ("duration_ms", "1800"), ("first_token_ms", "600")]
    return object(fixed, defaults: defaults, fields: fields)
}

// MARK: Decoding

@Test func upstreamErrorEventsKeepOnlyTheirTimingAndAccount() {
    let events = UpstreamErrorEvent.parse(eventsJSON)
    #expect(events == [
        UpstreamErrorEvent(accountID: 9, accountName: "账号 A", upstreamStatusCode: 429, atUnixMs: 1_792_114_865_000, startedAtUnixMs: 1_792_114_864_600,
                           durationMs: 400, kind: "http_error", droppedEarlierAttempts: 2),
        UpstreamErrorEvent(accountID: 9, upstreamStatusCode: 504, atUnixMs: 1_792_114_866_000, kind: "failover")
    ])
    #expect(!String(describing: events).contains("never-decode"))
    for broken: String? in [nil, "", "not json", #"{"at_unix_ms":1}"#, #"[1,"x"]"#, "null"] { #expect(UpstreamErrorEvent.parse(broken).isEmpty) }
    let odd = UpstreamErrorEvent.parse(#"[{"account_id":"9","account_name":"","upstream_status_code":"429","at_unix_ms":"x","started_at_unix_ms":0,"duration_ms":-5,"kind":7,"dropped_earlier_attempts":"2"},3]"#)
    #expect(odd == [UpstreamErrorEvent()])
}

@Test func errorDetailReusesTheRecordAndDropsRawBodies() throws {
    let detail = try decoded(RequestErrorDetail.self, errorJSON())
    #expect(detail.id == 61 && detail.record.statusCode == 504 && detail.record.model == "claude-example")
    #expect(detail.upstreamStatusCode == 429 && detail.upstreamLatencyMs == 3000 && detail.responseLatencyMs == 158)
    #expect(detail.authLatencyMs == 12 && detail.routingLatencyMs == 30 && !detail.isBusinessLimited)
    #expect(detail.apiKeyPrefix == "sk-abcde")
    #expect(detail.upstreamEvents.map(\.upstreamStatusCode) == [429, 504])
    #expect(detail.upstreamErrorMessage == "slow down [已隐藏凭据]")
    let text = String(describing: detail)
    #expect(!text.contains("never-decode") && !text.contains("never-leak") && !text.contains("203.0.113.9"))

    let old = try decoded(RequestErrorDetail.self, #"{"id":7,"created_at":"2026-10-16T01:41:07Z","request_id":"r","phase":"request","type":"t","status_code":400,"platform":"","model":"m","resolved":false,"message":"bad"}"#)
    #expect(old.upstreamEvents.isEmpty && old.authLatencyMs == nil && old.routingLatencyMs == nil && old.apiKeyPrefix == nil && !old.isBusinessLimited)
    for raw in [#""""#, #""oops""#, "null", "[]", "42"] {
        let unparsed = try decoded(RequestErrorDetail.self, errorJSON(events: nil, fields: #","upstream_errors":"# + raw))
        #expect(unparsed.upstreamEvents.isEmpty)
    }
    let limited = try decoded(RequestErrorDetail.self, errorJSON(fields: #","api_key_prefix":"","is_business_limited":true"#))
    #expect(limited.apiKeyPrefix == nil && limited.isBusinessLimited)
}

@Test func attemptsDecodeOldEventsAndUnknownValues() throws {
    let chain = try decoded(RequestAttempts.self, attemptsJSON)
    #expect(chain.requestID == "req-61" && chain.clientRequestID == clientRequestID && chain.clientStatusCode == 200)
    #expect(chain.errorLogIDs == [61] && chain.droppedEarlierAttempts == 0)
    #expect(chain.attempts.map(\.index) == [1, 2, 3] && chain.attempts.map(\.id) == [1, 2, 3])
    let failed = chain.attempts[0]
    #expect(failed.source == .upstreamError && failed.outcome == .failed && failed.accountID == 9 && failed.accountName == "账号 A")
    #expect(failed.startedAt == nil && failed.durationMs == nil && failed.firstTokenMs == nil && failed.endedAt != nil)
    #expect(failed.upstreamRequestID == nil && failed.kind == "http_error" && failed.stage == nil && failed.proxyID == nil)
    #expect(failed.proxyName == "direct/no_proxy" && failed.errorLogID == 61 && failed.usageID == nil && failed.upstreamStatusCode == 429)
    #expect(failed.message == "rate limited [已隐藏凭据]")
    let success = chain.attempts[1]
    #expect(success.source == .usage && success.outcome == .success && success.durationMs == 1800 && success.firstTokenMs == 600)
    #expect(success.startedAt == date("2026-10-16T01:41:05Z") && success.usageID == 77 && success.upstreamRequestID == "up-req-2" && success.message == nil)
    let unknown = chain.attempts[2]
    #expect(unknown.source == .unknown && unknown.outcome == .unknown && unknown.accountID == nil && unknown.upstreamStatusCode == nil)

    let empty = try decoded(RequestAttempts.self, emptyChainJSON)
    #expect(empty.attempts.isEmpty && empty.errorLogIDs.isEmpty && empty.clientRequestID == nil && empty.clientStatusCode == nil)
}

// MARK: Wire

@Test func errorDetailAndResolveWire() async throws {
    let transport = ScriptedTransport { request in request.httpMethod == "GET" ? okReply(errorJSON()) : okReply(#"{"ok":true}"#) }
    let client = detailClient(transport)
    _ = try await client.errorDetail(id: 61, kind: .request)
    _ = try await client.errorDetail(id: 62, kind: .upstream)
    try await client.setErrorResolved(id: 61, kind: .upstream, resolved: true)
    try await client.setErrorResolved(id: 62, kind: .request, resolved: false)
    let sent = await transport.requests
    #expect(sent.map(\.httpMethod) == ["GET", "GET", "PUT", "PUT"])
    #expect(sent.map { $0.url?.path } == ["/api/v1/admin/ops/request-errors/61", "/api/v1/admin/ops/upstream-errors/62",
                                         "/api/v1/admin/ops/upstream-errors/61/resolve", "/api/v1/admin/ops/request-errors/62/resolve"])
    #expect(sent[0].timeoutInterval == RequestTimeout.read && sent[2].timeoutInterval == RequestTimeout.unkeyedWrite)
    #expect(sent[2].httpBody == Data(#"{"resolved":true}"#.utf8) && sent[3].httpBody == Data(#"{"resolved":false}"#.utf8))
    #expect(sent.allSatisfy { sentHeader($0, "Idempotency-Key") == nil })

    let invalid = await thrownAPIError { _ = try await client.errorDetail(id: 0, kind: .request) }
    #expect(invalid?.kind == .validation)
    #expect(await transport.requests.count == 4)
}

@Test(arguments: [(503, "SERVICE_UNAVAILABLE", APIError.Kind.temporary), (403, "ACCESS_TOKEN_READ_ONLY", APIError.Kind.readOnly),
                  (404, "OPS_ERROR_NOT_FOUND", APIError.Kind.notFound), (404, "OPS_DISABLED", APIError.Kind.featureDisabled)])
func resolveRefusalIsThrownOnceUnchanged(status: Int, reason: String, kind: APIError.Kind) async {
    let transport = ScriptedTransport { _ in errorReply(status, reason: reason) }
    let error = await thrownAPIError { try await detailClient(transport).setErrorResolved(id: 61, kind: .request, resolved: true) }
    #expect(error?.reason == reason && error?.kind == kind && error?.statusCode == status)
    #expect(await transport.requests.count == 1)
}

@Test func attemptsPathEncodesOneSegmentAndSendsAroundInUTC() async throws {
    let transport = ScriptedTransport { _ in okReply(emptyChainJSON) }
    let client = detailClient(transport)
    _ = try await client.requestAttempts(id: "client:8d3c", around: date("2026-10-16T09:41:07.25+08:00"))
    _ = try await client.requestAttempts(id: "ab cd?x#y%z+1", around: nil)
    let sent = await transport.requests
    #expect(sent[0].httpMethod == "GET" && sent[0].url?.path == "/api/v1/admin/ops/requests/client:8d3c/attempts")
    #expect(sentQuery(sent[0]) == [URLQueryItem(name: "around", value: "2026-10-16T01:41:07Z")])
    #expect(sent[0].timeoutInterval == RequestTimeout.read && sentHeader(sent[0], "Idempotency-Key") == nil)
    #expect(sent[1].url?.absoluteString == "https://requests.example.invalid/api/v1/admin/ops/requests/ab%20cd%3Fx%23y%25z+1/attempts")
}

@Test(arguments: ["a/b", "/", "", "  ", ".", "..", "a\u{0}b", String(repeating: "x", count: 257), String(repeating: "编", count: 86)])
func unqueryableRequestIDsAreNeverSent(id: String) async throws {
    let transport = ScriptedTransport { _ in okReply(emptyChainJSON) }
    let error = await thrownAPIError { _ = try await detailClient(transport).requestAttempts(id: id, around: nil) }
    #expect(error == .unqueryableRequestID)
    let thrown = try #require(error)
    #expect(AttemptsFailure(thrown) == .useFallback)
    #expect(!RequestAttemptsLookup.isQueryable(id))
    #expect(await transport.requests.isEmpty)
}

@Test func storedRequestIDFormsAreQueryable() {
    for id in [String(repeating: "x", count: 256), "client:8d3c", "probe:7", "local:a.b", "req 1?#%"] { #expect(RequestAttemptsLookup.isQueryable(id)) }
}

@Test func ambiguousRequestPicksTheIDClosestToTheRow() async throws {
    let metadata = ["client_request_ids": "c-new, c-mid ,c-old", "client_request_id_times": "2026-10-16T03:00:00.5Z,2026-10-16T02:00:00Z,2026-10-16T01:00:00Z"]
    let ambiguous = AmbiguousRequest(metadata: metadata)
    #expect(ambiguous.candidates.map(\.clientRequestID) == ["c-new", "c-mid", "c-old"])
    #expect(ambiguous.candidates.last?.latestAt == date("2026-10-16T01:00:00Z"))
    #expect(ambiguous.closest(to: date("2026-10-16T01:10:00Z")) == "c-old")
    #expect(ambiguous.closest(to: date("2026-10-16T02:20:00Z")) == "c-mid")
    #expect(ambiguous.closest(to: nil) == "c-new")
    let tied = AmbiguousRequest(metadata: ["client_request_ids": "a,b", "client_request_id_times": "2026-10-16T03:00:00Z,2026-10-16T02:00:00Z"])
    #expect(tied.closest(to: date("2026-10-16T02:30:00Z")) == "a")
    #expect(AmbiguousRequest(metadata: ["client_request_ids": "a,b"]).closest(to: date("2026-10-16T02:30:00Z")) == "a")
    let misaligned = AmbiguousRequest(metadata: ["client_request_ids": "a,b", "client_request_id_times": "2026-10-16T01:00:00Z"])
    #expect(misaligned.candidates.allSatisfy { $0.latestAt == nil } && misaligned.closest(to: date("2026-10-16T02:30:00Z")) == "a")
    #expect(AmbiguousRequest(metadata: [:]).closest(to: nil) == nil)

    let transport = ScriptedTransport { _ in
        errorReply(409, reason: "OPS_REQUEST_AMBIGUOUS", extra: #","metadata":{"client_request_ids":"c-new,c-old","client_request_id_times":"2026-10-16T03:00:00Z,2026-10-16T01:00:00Z"}"#)
    }
    let refusal = await thrownAPIError { _ = try await detailClient(transport).requestAttempts(id: "req-61", around: date("2026-10-16T01:20:00Z")) }
    let error = try #require(refusal)
    #expect(await transport.requests.count == 1)
    let thrown = try #require(AmbiguousRequest(error: error))
    #expect(thrown.closest(to: date("2026-10-16T01:20:00Z")) == "c-old")
    #expect(AttemptsFailure(error) == .ambiguous(thrown))
    #expect(AmbiguousRequest(error: .server(status: 409, reason: "OPS_REQUEST_NOT_FOUND")) == nil)
}

@Test func attemptsFailureClassification() {
    let fallbacks: [APIError] = [.server(status: 404, reason: "OPS_REQUEST_NOT_FOUND"), .server(status: 400, reason: "INVALID_REQUEST_ID"),
                                 .server(status: 400, reason: "INVALID_AROUND"), .server(status: 404, envelope: nil), .server(status: 404, reason: nil),
                                 .server(status: 409, reason: "OPS_REQUEST_AMBIGUOUS"), .unqueryableRequestID]
    for error in fallbacks { #expect(AttemptsFailure(error) == .useFallback) }
    #expect(AttemptsFailure(APIError.server(status: 404, reason: "OPS_DISABLED")) == .opsDisabled)
    let failures: [any Error] = [APIError.server(status: 503, reason: nil), APIError.server(status: 403, reason: "FORBIDDEN"),
                                 APIError.server(status: 400, reason: "VALIDATION_ERROR"), APIError.transport(URLError(.timedOut)), URLError(.cancelled)]
    for error in failures { #expect(AttemptsFailure(error) == .failed) }
}

// MARK: Presentation

@Test func detailStyleTitleAndSubtitle() throws {
    typealias P = RequestDetailPresentation
    #expect(P.style(kind: nil, statusCode: 200) == .success)
    #expect(P.style(kind: .upstream, statusCode: 200) == .recovered && P.style(kind: .upstream, statusCode: 399) == .recovered)
    let failedCases: [(ErrorLogKind, Int)] = [(.upstream, 429), (.upstream, 0), (.request, 200), (.request, 504)]
    for (kind, status) in failedCases { #expect(P.style(kind: kind, statusCode: status) == .failed) }
    #expect(P.style(kind: .upstream, statusCode: nil) == .failed)
    let kinds: [ErrorLogKind?] = [nil, .request, .upstream]
    #expect(kinds.map { P.title(kind: $0) } == ["请求详情", "失败请求", "上游错误"])
    #expect(kinds.map { P.sourceName(kind: $0) } == ["用量明细", "错误请求", "上游错误"])
    #expect(P.subtitle(createdAt: date("2026-10-16T01:41:07.9Z"), kind: .request, timeZone: siteZone) == "10/16 09:41:07 · 错误请求")
    #expect(P.subtitle(createdAt: date("2026-03-05T01:02:03Z"), kind: .upstream, timeZone: siteZone) == "3/5 09:02:03 · 上游错误")
    #expect(P.subtitle(createdAt: nil, kind: nil, timeZone: siteZone) == "— · 用量明细")
}

@Test func phaseOwnerAndRequestTypeNames() throws {
    typealias P = RequestDetailPresentation
    let phases = ["request", "auth", "account_auth", "routing", "upstream", "network", "internal", "brand_new"]
    #expect(phases.map { P.phaseName($0) } == ["请求校验", "鉴权", "账号鉴权", "路由", "上游", "网络", "网关内部", "brand_new"])
    #expect(["client", "provider", "platform", "someone"].map { P.ownerName($0) } == ["客户端", "上游服务商", "平台配置", "someone"])
    #expect(P.phaseName(nil) == nil && P.phaseName(" ") == nil && P.ownerName("") == nil)
    let full = try decoded(RequestErrorDetail.self, errorJSON()).record
    #expect(P.causeLine(full) == "上游 · 上游服务商 · P1")
    let bare = try decoded(RequestErrorDetail.self, errorJSON(fields: #","phase":"","error_owner":"","severity":"""#)).record
    #expect(P.causeLine(bare) == nil)
    let ownerless = try decoded(RequestErrorDetail.self, errorJSON(fields: #","error_owner":"","severity":"P0""#)).record
    #expect(P.causeLine(ownerless) == "上游 · P0")

    for type in UsageRequestType.allCases {
        #expect(P.requestTypeName(type.rawValue, context: .list) == type.title && P.requestTypeName(type.rawValue, context: .detail) == type.detailTitle)
    }
    #expect(P.requestTypeName("sync", context: .detail) == "非流式" && P.requestTypeName("ws_v2", context: .detail) == "WebSocket")
    for raw: String? in [nil, "", "unknown", "carrier"] { #expect(P.requestTypeName(raw, context: .list) == "—") }
    #expect(P.requestTypeName(code: 2, stream: false, context: .detail) == "流式")
    #expect(P.requestTypeName(code: 3, stream: nil, context: .list) == "WS")
    #expect(P.requestTypeName(code: 0, stream: true, context: .detail) == "流式")
    #expect(P.requestTypeName(code: 6, stream: false, context: .detail) == "非流式" && P.requestTypeName(code: nil, stream: false, context: .list) == "同步")
    #expect(P.requestTypeName(code: nil, stream: nil, context: .detail) == "—" && P.requestTypeName(code: 0, stream: nil, context: .list) == "—")
}

@Test func statusLineCodesAndTones() throws {
    typealias P = RequestDetailPresentation
    #expect(P.successStatusLine == RequestStatusLine(label: "成功", badge: "200", tone: .ok, capsule: nil))
    let recovered = try decoded(RequestErrorDetail.self, errorJSON(status: 200, fields: #","message":"Recovered upstream error 429: slow down","upstream_status_code":503"#))
    #expect(P.errorStatusLine(record: recovered.record, kind: .upstream, detail: recovered, clientStatusCode: nil)
            == RequestStatusLine(label: "上游失败", badge: "503", tone: .critical, capsule: nil))
    let listRow = try decoded(RequestErrorDetail.self, errorJSON(status: 200, fields: #","message":"Recovered upstream error 429: slow down","upstream_status_code":null"#)).record
    #expect(P.errorStatusLine(record: listRow, kind: .upstream, detail: nil, clientStatusCode: nil) == RequestStatusLine(label: "上游失败", badge: "429", tone: .caution, capsule: nil))
    let auth = try decoded(RequestErrorDetail.self, errorJSON(status: 200, fields: #","phase":"account_auth","message":"x","upstream_status_code":null"#)).record
    #expect(P.errorStatusLine(record: auth, kind: .upstream, detail: nil, clientStatusCode: nil).badge == "鉴权")
    let other = try decoded(RequestErrorDetail.self, errorJSON(status: 200, fields: #","message":"x","upstream_status_code":null"#)).record
    #expect(P.errorStatusLine(record: other, kind: .upstream, detail: nil, clientStatusCode: nil) == RequestStatusLine(label: "上游失败", badge: "恢复", tone: .neutral, capsule: nil))
    #expect(P.recoveryNote(other) == "已自动重试成功，客户端收到 200")

    let failed = try decoded(RequestErrorDetail.self, errorJSON())
    #expect(P.errorStatusLine(record: failed.record, kind: .request, detail: failed, clientStatusCode: nil) == RequestStatusLine(label: "失败", badge: "504", tone: .critical, capsule: .critical))
    #expect(P.errorStatusLine(record: failed.record, kind: .upstream, detail: failed, clientStatusCode: 429) == RequestStatusLine(label: "失败", badge: "429", tone: .caution, capsule: .caution))
    let limited = try decoded(RequestErrorDetail.self, errorJSON(status: 429, fields: #","is_business_limited":true"#))
    #expect(P.errorStatusLine(record: limited.record, kind: .request, detail: limited, clientStatusCode: nil) == RequestStatusLine(label: "失败", badge: "429", tone: .neutral, capsule: .neutral))
    let missing = try decoded(RequestErrorDetail.self, errorJSON(status: 0)).record
    #expect(P.errorStatusLine(record: missing, kind: .request, detail: nil, clientStatusCode: nil) == RequestStatusLine(label: "失败", badge: "—", tone: .neutral, capsule: .neutral))
}

@Test func messageModelCostAndResolvedNote() throws {
    typealias P = RequestDetailPresentation
    let detail = try decoded(RequestErrorDetail.self, errorJSON())
    #expect(P.errorMessage(record: detail.record, detail: detail) == "slow down [已隐藏凭据]")
    let plain = try decoded(RequestErrorDetail.self, errorJSON(fields: #","upstream_error_message":"""#))
    #expect(P.errorMessage(record: plain.record, detail: plain) == "upstream timeout [已隐藏凭据]")
    let blank = try decoded(RequestErrorDetail.self, errorJSON(fields: #","upstream_error_message":"  ","message":"""#))
    #expect(P.errorMessage(record: blank.record, detail: blank) == "上游返回错误")
    #expect(P.upstreamModel(model: "m", upstream: "u") == "u")
    #expect(P.upstreamModel(model: "m", upstream: "m") == nil && P.upstreamModel(model: "m", upstream: "") == nil && P.upstreamModel(model: "m", upstream: nil) == nil)

    let usage = try decoded(UsageRequestRecord.self, usageJSON())
    #expect(P.costCells(usage) == [RequestCostCell(label: "实际扣费", value: "$0.1235"), RequestCostCell(label: "账号成本", value: "$0.1200"),
                                   RequestCostCell(label: "标准", value: "$0.5000")])
    #expect(P.followerCostNote(usage) == nil)
    let follower = try decoded(UsageRequestRecord.self, usageJSON(#","provider_cost_recorded":false,"account_cost":"0.37","actual_cost":null"#))
    #expect(P.costCells(follower).map(\.value) == ["—", "$0.0000", "$0.5000"])
    #expect(P.followerCostNote(follower) == "合并探测的跟随请求，没有上游成本")

    #expect(P.resolvedNote(detail.record, timeZone: siteZone) == "已处理 · 值班 · 10/16 09:52")
    let nameless = try decoded(RequestErrorDetail.self, errorJSON(fields: #","resolved_by_user_name":"""#)).record
    #expect(P.resolvedNote(nameless, timeZone: siteZone) == "已处理 · 10/16 09:52")
    let open = try decoded(RequestErrorDetail.self, errorJSON(fields: #","resolved":false"#)).record
    #expect(P.resolvedNote(open, timeZone: siteZone) == nil)
    let undated = try decoded(RequestErrorDetail.self, errorJSON(fields: #","resolved_at":null"#)).record
    #expect(P.resolvedNote(undated, timeZone: siteZone) == nil)
}

@Test func timingFallsBackToPhaseSumAndKeepsFirstTokenVisible() throws {
    typealias P = RequestDetailPresentation
    #expect(P.timing(firstTokenMs: 600, durationMs: 3200) == RequestTiming(firstToken: "0.6s", total: "3.2s", isEstimated: false, firstTokenShare: 0.1875))
    #expect(P.timing(firstTokenMs: 50, durationMs: 10_000).firstTokenShare == P.minimumFirstTokenShare)
    #expect(P.timing(firstTokenMs: 5_000, durationMs: 4_000).firstTokenShare == 1)
    #expect(P.timing(firstTokenMs: nil, durationMs: 3200) == RequestTiming(firstToken: "—", total: "3.2s", isEstimated: false, firstTokenShare: nil))
    #expect(P.timing(firstTokenMs: 10, durationMs: 0).firstTokenShare == nil)
    #expect(P.timing(firstTokenMs: nil, durationMs: nil, phases: [nil, nil]) == RequestTiming(firstToken: "—", total: "—", isEstimated: false, firstTokenShare: nil))

    let detail = try decoded(RequestErrorDetail.self, errorJSON(fields: #","time_to_first_token_ms":800"#))
    #expect(P.timing(detail.record, detail: detail) == RequestTiming(firstToken: "0.8s", total: "约 3.2s", isEstimated: true, firstTokenShare: 0.25))
    let partial = try decoded(RequestErrorDetail.self, errorJSON(fields: #","auth_latency_ms":null,"routing_latency_ms":null"#))
    #expect(P.timing(partial.record, detail: partial).total == "约 3.2s")
    let timed = try decoded(RequestErrorDetail.self, errorJSON(fields: #","duration_ms":4100"#))
    #expect(P.timing(timed.record, detail: timed).total == "4.1s" && !P.timing(timed.record, detail: timed).isEstimated)
    #expect(P.timing(timed.record, detail: nil).total == "4.1s")
    let usage = try decoded(UsageRequestRecord.self, usageJSON())
    #expect(P.timing(usage) == RequestTiming(firstToken: "0.6s", total: "1.8s", isEstimated: false, firstTokenShare: 1.0 / 3))
}

@Test func attemptRowsFollowTheFiveSubtitleRules() throws {
    typealias P = RequestDetailPresentation
    func attempt(_ fields: String, outcome: String = "failed") -> String { #"{"source":"upstream_error","outcome":""# + outcome + #"","# + fields + "}" }
    let json = #"{"request_id":"r","client_status_code":500,"attempts":["#
        + [attempt(#""index":1,"account_id":9,"account_name":"账号 A","upstream_status_code":429,"duration_ms":400"#),
           attempt(#""index":2,"account_id":9,"account_name":"","upstream_status_code":529,"duration_ms":null"#),
           attempt(#""index":3,"account_id":12,"account_name":"账号 B","upstream_status_code":200,"duration_ms":1800,"upstream_request_id":"up-3""#, outcome: "partial"),
           attempt(#""index":4,"account_id":null,"upstream_status_code":null,"duration_ms":100"#),
           attempt(#""index":5,"account_id":12,"account_name":"账号 B","upstream_status_code":500,"duration_ms":182000"#)].joined(separator: ",")
        + #"],"dropped_earlier_attempts":3}"#
    let chain = try decoded(RequestAttempts.self, json)
    let rows = P.attemptRows(chain)
    #expect(rows.map(\.id) == [1, 2, 3, 4, 5])
    #expect(rows.map(\.title) == ["账号 A", "#9", "账号 B", "未知账号", "账号 B"])
    #expect(rows.map(\.subtitle) == ["失败，同一账号重试", "失败，切换到 账号 B 重试", "已计费，但请求最终失败", "失败，切换到 账号 B 重试", "失败，错误返回客户端"])
    #expect(rows.map(\.trailing) == ["429 · 0.4s", "529 · —", "200 · 1.8s", "— · 0.1s", "500 · 182s"])
    #expect(rows.map(\.tone) == [.caution, .critical, .ok, .neutral, .critical])
    #expect(rows.map(\.accountID) == [9, 9, 12, nil, 12])
    #expect(P.lastUpstreamRequestID(chain) == nil)
    #expect(P.droppedNote(chain.droppedEarlierAttempts) == "更早的 3 次尝试因队列上限没有记录" && P.droppedNote(0) == nil)
    #expect(P.attemptsMeta(count: rows.count, clientStatusCode: chain.clientStatusCode) == "5 次 · 返回客户端 500")
    #expect(P.attemptsMeta(count: 1, clientStatusCode: nil) == "1 次")

    let success = try decoded(RequestAttempts.self, attemptsJSON)
    #expect(P.attemptRows(success).map(\.subtitle) == ["失败，切换到 账号 B 重试", "成功，结果返回客户端", "失败，错误返回客户端"])
    let twoTries = try decoded(RequestAttempts.self, attemptsJSON.replacingOccurrences(of: #",{"source":"carrier","outcome":"exploded","account_id":null}"#, with: ""))
    #expect(P.lastUpstreamRequestID(twoTries) == "up-req-2")

    #expect(P.showsAttempts(style: .success, count: 1) == false && P.showsAttempts(style: .success, count: 2))
    #expect(P.showsAttempts(style: .failed, count: 1) && P.showsAttempts(style: .recovered, count: 1) && !P.showsAttempts(style: .failed, count: 0))
}

@Test func fallbackRowsEstimateDurationsAndAppendTheSuccess() throws {
    typealias P = RequestDetailPresentation
    let events = [UpstreamErrorEvent(accountID: 9, accountName: "账号 A", upstreamStatusCode: 429, atUnixMs: 1_000, startedAtUnixMs: 600, droppedEarlierAttempts: 2),
                  UpstreamErrorEvent(accountID: 9, upstreamStatusCode: 504, atUnixMs: 2_500, kind: "failover"),
                  UpstreamErrorEvent(accountName: "账号 B", upstreamStatusCode: 529, atUnixMs: 2_000),
                  UpstreamErrorEvent(accountName: "账号 B", upstreamStatusCode: 503, durationMs: 300)]
    let usage = try decoded(UsageRequestRecord.self, usageJSON())
    let rows = P.fallbackRows(events: events, success: usage)
    #expect(rows.map(\.id) == [1, 2, 3, 4, 5])
    #expect(rows.map(\.trailing) == ["429 · 0.4s", "504 · 约 1.5s", "529 · —", "503 · 0.3s", "200 · 1.8s"])
    #expect(rows.map(\.subtitle) == ["失败，同一账号重试", "失败，切换到 账号 B 重试", "失败，同一账号重试", "失败，同一账号重试", "成功，结果返回客户端"])
    #expect(rows.last == AttemptRow(id: 5, title: "账号 B", accountID: 12, trailing: "200 · 1.8s", subtitle: "成功，结果返回客户端", tone: .ok))
    #expect(P.fallbackRows(events: events, success: nil).last?.subtitle == "失败，错误返回客户端")
    #expect(P.fallbackRows(events: [UpstreamErrorEvent(upstreamStatusCode: 429, atUnixMs: 1_000)], success: nil).map(\.trailing) == ["429 · —"])
    #expect(P.fallbackRows(events: [], success: nil).isEmpty)
    #expect(P.fallbackDropped(events) == 2 && P.fallbackDropped([]) == 0)
}

@Test func chainLookupIDsAndFallbackFilter() throws {
    typealias P = RequestDetailPresentation
    let record = try decoded(RequestErrorDetail.self, errorJSON()).record
    #expect(P.attemptsID(forError: record) == clientRequestID)
    let slashed = try decoded(RequestErrorDetail.self, errorJSON(fields: #","client_request_id":"","request_id":"gw/1""#)).record
    #expect(P.attemptsID(forError: slashed) == nil)
    let plain = try decoded(RequestErrorDetail.self, errorJSON(fields: #","client_request_id":"","request_id":"req-9""#)).record
    #expect(P.attemptsID(forError: plain) == "req-9")
    let usage = try decoded(UsageRequestRecord.self, usageJSON())
    #expect(P.attemptsID(forUsage: usage) == "client:" + clientRequestID)
    let gateway = try decoded(UsageRequestRecord.self, usageJSON(#","request_id":"gw/1""#))
    #expect(P.attemptsID(forUsage: gateway) == nil)

    #expect(P.fallbackSuccessFilter(clientRequestID: clientRequestID) == RequestLogFilter(time: .none, requestID: "client:" + clientRequestID, pageSize: 1))
    #expect(P.fallbackSuccessFilter(clientRequestID: " ") == nil && P.fallbackSuccessFilter(clientRequestID: nil) == nil)
}
