import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 00 §3.4 rule 2 (D29): the root alert's “详情” is S0-02's diagnostics plus the time, never the server's message or metadata.

private let occurred = ServerTime.parseTimestamp("2026-10-22T01:41:00Z")!
private func failure(_ status: Int, _ body: String, headers: [String: String] = [:]) -> APIError {
    APIError.from(HTTPResponse(statusCode: status, headers: headers, data: Data(body.utf8)))
}

@Test func detailsListStatusReasonRequestIDAndUTCTime() throws {
    let error = failure(409, #"{"code":409,"reason":"IDEMPOTENCY_KEY_CONFLICT"}"#, headers: ["X-Request-ID": "rid-1"])
    let details = try #require(ErrorDetails(error, occurredAt: occurred))
    #expect(details.rows.map(\.id) == ["status", "reason", "request-id", "time"])
    #expect(details.rows.map(\.label) == ["HTTP 状态", "错误码", "请求 ID", "时间"])
    #expect(details.rows.map(\.value) == ["409", "IDEMPOTENCY_KEY_CONFLICT", "rid-1", "2026-10-22T01:41:00Z"])
    #expect(details.message == error.localizedDescription)
    #expect(details.text == "HTTP 状态：409\n错误码：IDEMPOTENCY_KEY_CONFLICT\n请求 ID：rid-1\n时间：2026-10-22T01:41:00Z")
}

@Test func serverMessageAndMetadataNeverReachTheDetails() throws {
    let body = #"{"code":400,"reason":"VALIDATION_ERROR","message":"secret https://upstream.example.invalid/?key=sk-fixture","metadata":{"field":"sk-fixture"}}"#
    let details = try #require(ErrorDetails(failure(400, body, headers: ["X-Request-ID": "rid-2"]), occurredAt: occurred))
    for fragment in ["secret", "upstream", "sk-fixture"] {
        #expect(!details.text.contains(fragment)); #expect(!details.message.contains(fragment))
    }
    #expect(details.rows.prefix(3).map(\.value) == ["400", "VALIDATION_ERROR", "rid-2"])
}

@Test func nonJSONAndMiddlewareErrorsKeepTheirRequestID() throws {
    let html = try #require(ErrorDetails(failure(503, "<html>busy</html>", headers: ["X-Request-ID": "rid-3"]), occurredAt: occurred))
    #expect(html.rows.prefix(3).map(\.value) == ["503", "—", "rid-3"])
    let middleware = failure(401, #"{"code":"INVALID_TOKEN","reason":"INVALID_TOKEN"}"#, headers: ["x-request-id": "rid-4"])
    #expect(try #require(ErrorDetails(middleware, occurredAt: occurred)).rows.prefix(3).map(\.value) == ["401", "INVALID_TOKEN", "rid-4"])
}

@Test func onlyAPIErrorsHaveDetails() {
    #expect(ErrorDetails(CancellationError()) == nil)
    #expect(ErrorDetails(URLError(.badURL)) == nil)
    let unreachable = APIError(kind: .transport, message: "无法连接站点")
    #expect(ErrorDetails(unreachable, occurredAt: occurred)?.rows.map(\.value) == ["—", "—", "—", "2026-10-22T01:41:00Z"])
}
