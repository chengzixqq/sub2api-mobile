import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
import Testing
@testable import Sub2Core

// 00 §3.4 rule 3: one line per attempt with method, path template, status, reason and X-Request-ID only.

@Test(arguments: [
    ("admin/users/42/balance", "admin/users/:id/balance"),
    ("admin/access-tokens/5", "admin/access-tokens/:id"),
    ("auth/sessions/0a1b2c3d4e5f6071", "auth/sessions/:id"),
    ("admin/push/devices/12/test", "admin/push/devices/:id/test"),
    ("/api/v1/admin/accounts/9", "admin/accounts/:id"),
    ("admin/redeem-codes/3f2504e0-4f89-41d3-9a0c-0305e82c3301", "admin/redeem-codes/:id"),
    ("admin/dashboard/snapshot-v2", "admin/dashboard/snapshot-v2"),
    ("auth/login/2fa", "auth/login/2fa"),
    ("auth/sessions", "auth/sessions"),
    ("admin/accounts/today-stats/batch", "admin/accounts/today-stats/batch"),
    ("admin/me", "admin/me"),
    ("admin/users?search=a@b.example", "admin/users"),
    ("admin/ops/requests/client:0a1b-x/attempts", "admin/ops/requests/:id/attempts"),
    ("admin/ops/requests", "admin/ops/requests")
])
func pathTemplateMasksIdentifiers(path: String, template: String) {
    #expect(RequestLog.pathTemplate(path) == template)
}

@Test func logLineCarriesOnlyAllowedFields() {
    #expect(RequestLog.line(method: "POST", path: "admin/users/7/balance", status: 409, reason: "IDEMPOTENCY_IN_PROGRESS", requestID: "rid-1")
            == "POST admin/users/:id/balance 409 IDEMPOTENCY_IN_PROGRESS rid-1")
    #expect(RequestLog.line(method: "GET", path: "admin/me", status: nil, reason: nil, requestID: nil) == "GET admin/me - - -")
}

@Test(arguments: ["Bearer abc", "TOKEN_EXPIRED\nINJECTED", "token_expired", String(repeating: "A", count: 65), ""])
func reasonOutsideTheCodeAlphabetIsDropped(reason: String) {
    #expect(RequestLog.line(method: "GET", path: "admin/me", status: 401, reason: reason, requestID: nil) == "GET admin/me 401 - -")
}

@Test func requestIDKeepsVisibleASCIIUpToSixtyFourBytes() {
    for kept in ["3f2504e0-4f89-41d3-9a0c-0305e82c3301", "client:3f2504e0-4f89-41d3-9a0c-0305e82c3301", String(repeating: "r", count: 64)] {
        #expect(RequestLog.line(method: "GET", path: "admin/me", status: 200, reason: nil, requestID: kept) == "GET admin/me 200 - \(kept)")
    }
    for dropped in ["rid 1", "rid\n1", "编号", String(repeating: "r", count: 65)] {
        #expect(RequestLog.line(method: "GET", path: "admin/me", status: 200, reason: nil, requestID: dropped) == "GET admin/me 200 - -")
    }
}

@Test func attemptLineReadsReasonOnlyFromErrorBodiesAndNeverTheQuery() {
    var request = URLRequest(url: URL(string: "https://logs.example.invalid/api/v1/admin/users/7/balance?search=a%40b.example")!)
    request.httpMethod = "POST"
    request.setValue("client-rid", forHTTPHeaderField: "X-Request-ID")
    let body = #"{"code":409,"reason":"IDEMPOTENCY_IN_PROGRESS","message":"secret sk-fixture","metadata":{"retry_after":"5"}}"#
    let refused = HTTPResponse(statusCode: 409, headers: ["x-request-id": "server-rid"], data: Data(body.utf8))
    #expect(RequestLog.line(for: request, response: refused) == "POST admin/users/:id/balance 409 IDEMPOTENCY_IN_PROGRESS server-rid")
    let accepted = HTTPResponse(statusCode: 200, data: Data(#"{"code":0,"reason":"IGNORED","data":{}}"#.utf8))
    #expect(RequestLog.line(for: request, response: accepted) == "POST admin/users/:id/balance 200 - client-rid")
    #expect(RequestLog.line(for: request, response: nil) == "POST admin/users/:id/balance - - client-rid")
    let html = HTTPResponse(statusCode: 502, data: Data("<html>502 Bad Gateway</html>".utf8))
    #expect(RequestLog.line(for: URLRequest(url: URL(string: "https://logs.example.invalid/api/v1/admin/me")!), response: html) == "GET admin/me 502 - -")
}

// S0-LOW-B: what the client hands to the log, collected instead of the unified log.

private final class LoggedLines: Sendable {
    private let lines = Mutex<[(line: String, failed: Bool)]>([])
    var sink: RequestLog.Sink { { [self] line, failed in lines.withLock { $0.append((line, failed)) } } }
    var all: [String] { lines.withLock { $0.map(\.line) } }
    var failures: [Bool] { lines.withLock { $0.map(\.failed) } }
}

@Test func everyAttemptLogsOneLine() async throws {
    let transport = ScriptedTransport(script: [.reply(errorReply(502)), .fail(URLError(.timedOut)),
                                               .reply(okReply(stubUserJSON, headers: ["x-request-id": "rid-3"]))])
    let client = APIClient(server: stubServer(), credential: .adminKey("fixture"), transport: transport, requestClock: .immediate)
    let logged = LoggedLines()
    await client.logRequests(to: logged.sink)
    _ = try await client.user(id: 7)
    #expect(logged.all == ["GET admin/users/:id 502 - -", "GET admin/users/:id - - -", "GET admin/users/:id 200 - rid-3"])
    #expect(logged.failures == [true, true, false])
}

@Test(.timeLimit(.minutes(1))) func cancelledAttemptLogsNothing() async throws {
    let transport = ScriptedTransport { _ in try await Task.sleep(for: .seconds(60)); return okReply(stubUserJSON) }
    let client = APIClient(server: stubServer(), credential: .adminKey("fixture"), transport: transport, requestClock: .immediate)
    let logged = LoggedLines()
    await client.logRequests(to: logged.sink)
    let reading = Task { try await client.user(id: 7) }
    while await transport.requests.isEmpty { await Task.yield() }
    await client.cancelAll()
    _ = await reading.result
    #expect(logged.all.isEmpty)
}

/// 00 §3.4 rule 3 for the account test stream too: a refused stream's line carries the reason read from its error body.
@Test func refusedTestStreamLogsTheReasonFromItsBody() async throws {
    let body = #"{"code":403,"reason":"ACCESS_TOKEN_READ_ONLY","message":"read only"}"#
    let transport = ScriptedTransport(stream: { _ in
        HTTPStreamResponse(statusCode: 403, headers: ["x-request-id": "rid-sse"], bytes: AsyncThrowingStream { $0.yield(Data(body.utf8)); $0.finish() })
    }) { _ in throw URLError(.unsupportedURL) }
    let client = APIClient(server: stubServer(), credential: .accessToken("sat_fixture"), transport: transport, requestClock: .immediate)
    let logged = LoggedLines()
    await client.logRequests(to: logged.sink)
    let error = await thrownAPIError { _ = try await client.testAccount(id: 7, model: nil) }
    #expect(error?.reason == "ACCESS_TOKEN_READ_ONLY")
    #expect(logged.all == ["POST admin/accounts/:id/test 403 ACCESS_TOKEN_READ_ONLY rid-sse"])
    #expect(logged.failures == [true])
}
