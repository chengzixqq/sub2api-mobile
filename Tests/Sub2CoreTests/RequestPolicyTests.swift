import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

@Test func requestClassInferenceAndDefaultTimeouts() {
    #expect(RequestClass.inferred(method: "GET") == .read)
    for method in ["POST", "PUT", "DELETE", "PATCH"] { #expect(RequestClass.inferred(method: method) == .unkeyedWrite) }
    let key = UUID()
    #expect(RequestClass.read.defaultTimeout == 20); #expect(RequestClass.readBatch.defaultTimeout == 20)
    #expect(RequestClass.unkeyedWrite.defaultTimeout == 30); #expect(RequestClass.keyedWrite(key: key).defaultTimeout == 35)
    #expect(RequestClass.auth.defaultTimeout == 20)
    #expect(RequestClass.keyedWrite(key: key).idempotencyKey == key.uuidString.lowercased())
    #expect(RequestClass.keyedWrite(key: key).idempotencyKey?.count == 36)
    for other in [RequestClass.read, .readBatch, .unkeyedWrite, .auth] { #expect(other.idempotencyKey == nil) }
    #expect(RequestClass.read.isRead && RequestClass.readBatch.isRead)
    #expect(!RequestClass.unkeyedWrite.isRead && !RequestClass.keyedWrite(key: key).isRead && !RequestClass.auth.isRead)
    #expect(RequestClass.read.retriesAutomatically && RequestClass.readBatch.retriesAutomatically)
    #expect(!RequestClass.keyedWrite(key: key).retriesAutomatically && !RequestClass.unkeyedWrite.retriesAutomatically)
    let resending = [RequestClass.read, .readBatch, .keyedWrite(key: key), .unkeyedWrite].allSatisfy { $0.resendsAfterTokenRefresh }
    #expect(resending)
    #expect(!RequestClass.auth.resendsAfterTokenRefresh)
}

@Test func timeoutConstantsFollowSpecTable() {
    #expect(RequestTimeout.probe == 15); #expect(RequestTimeout.authentication == 20); #expect(RequestTimeout.read == 20)
    #expect(RequestTimeout.home == 15); #expect(RequestTimeout.aggregate == 45); #expect(RequestTimeout.dashboardStats == 90)
    #expect(RequestTimeout.unkeyedWrite == 30); #expect(RequestTimeout.keyedWrite == 35); #expect(RequestTimeout.keyedBulk == 65)
    #expect(RequestTimeout.batchRefresh == 125)
}

@Test func readRetryDelaysAddBoundedJitterAndStopAfterTwo() {
    let read = RequestClass.read
    #expect(read.automaticRetryDelay(after: .network, attempt: 0, jitter: .zero) == .seconds(1))
    #expect(read.automaticRetryDelay(after: .network, attempt: 0, jitter: .milliseconds(500)) == .milliseconds(1_500))
    #expect(read.automaticRetryDelay(after: .status(502, marker: nil), attempt: 1, jitter: .zero) == .seconds(3))
    #expect(RequestClass.readBatch.automaticRetryDelay(after: .network, attempt: 1, jitter: .milliseconds(500)) == .milliseconds(3_500))
    #expect(read.automaticRetryDelay(after: .network, attempt: 2, jitter: .zero) == nil)
    #expect(read.automaticRetryDelay(after: .network, attempt: 0, jitter: .seconds(4)) == .milliseconds(1_500))
    #expect(read.automaticRetryDelay(after: .network, attempt: 0, jitter: .milliseconds(-200)) == .seconds(1))
    #expect(read.automaticRetryDelay(after: .status(500, marker: nil), attempt: 0, jitter: .zero) == nil)
    for other in [RequestClass.unkeyedWrite, .keyedWrite(key: UUID()), .auth] {
        #expect(other.automaticRetryDelay(after: .network, attempt: 0, jitter: .zero) == nil)
        #expect(other.automaticRetryDelay(after: .status(503, marker: nil), attempt: 0, jitter: .zero) == nil)
    }
}

@Test func retryableFailuresMatchReadTable() {
    for code in [URLError.Code.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed] {
        #expect(RequestPolicy.isRetryableNetworkError(URLError(code)), "\(code)")
    }
    for error: any Error in [URLError(.unsupportedURL), URLError(.badURL), URLError(.cancelled), APIError.invalidResponse, CancellationError()] {
        #expect(!RequestPolicy.isRetryableNetworkError(error), "\(error)")
    }
    #expect(RequestPolicy.isRetryableStatus(502, marker: nil)); #expect(RequestPolicy.isRetryableStatus(504, marker: "ANYTHING"))
    #expect(RequestPolicy.isRetryableStatus(503, marker: nil)); #expect(RequestPolicy.isRetryableStatus(503, marker: "SERVICE_UNAVAILABLE"))
    #expect(!RequestPolicy.isRetryableStatus(503, marker: "ACCOUNT_STATS_UNAVAILABLE"))
    #expect(!RequestPolicy.isRetryableStatus(503, marker: "PUSH_NOT_CONFIGURED"))
    for status in [400, 401, 403, 404, 409, 429, 500] { #expect(!RequestPolicy.isRetryableStatus(status, marker: nil), "\(status)") }
    #expect(RequestFailure(response: okReply("{}")) == nil)
    #expect(RequestFailure(response: errorReply(503, reason: "SERVICE_UNAVAILABLE")) == .status(503, marker: "SERVICE_UNAVAILABLE"))
    #expect(RequestFailure(response: HTTPResponse(statusCode: 502, data: Data("<html>".utf8))) == .status(502, marker: nil))
    #expect(RequestFailure(error: URLError(.timedOut)) == .network)
    #expect(RequestFailure(error: URLError(.unsupportedURL)) == nil)
}

@Test func tokenRefreshIsRequestedForExpiredOrUnknownUnauthorized() {
    #expect(RequestPolicy.requiresTokenRefresh(status: 401, marker: "TOKEN_EXPIRED"))
    #expect(RequestPolicy.requiresTokenRefresh(status: 401, marker: nil))
    #expect(RequestPolicy.requiresTokenRefresh(status: 401, marker: "SOMETHING_NEW"))
    for known in ["TOKEN_REVOKED", "INVALID_TOKEN", "SESSION_BINDING_MISMATCH", "INVALID_ADMIN_KEY", "UNAUTHORIZED"] {
        #expect(!RequestPolicy.requiresTokenRefresh(status: 401, marker: known), "\(known)")
    }
    #expect(!RequestPolicy.requiresTokenRefresh(status: 403, marker: "TOKEN_EXPIRED"))
    #expect(!RequestPolicy.requiresTokenRefresh(status: 200, marker: nil))
}

@Test(arguments: [
    (401, "REFRESH_TOKEN_INVALID", RefreshVerdict.endSession), (401, "REFRESH_TOKEN_EXPIRED", .endSession),
    (401, "REFRESH_TOKEN_REUSED", .endSession), (401, "TOKEN_REVOKED", .endSession), (401, "SESSION_BINDING_MISMATCH", .endSession),
    (401, nil, .endSession), (401, "INVALID_TOKEN", .endSession), (400, nil, .endSession), (403, "USER_NOT_ACTIVE", .endSession),
    (403, "BACKEND_MODE_ADMIN_ONLY", .endSession), (429, "RATE_LIMITED", .keepSession), (500, nil, .keepSession),
    (502, nil, .keepSession), (503, "SERVICE_UNAVAILABLE", .keepSession), (504, nil, .keepSession), (408, nil, .keepSession),
    (404, nil, .keepSession), (403, "FORBIDDEN", .keepSession)
] as [(Int, String?, RefreshVerdict)])
func refreshVerdictCoversSpecTable(status: Int, reason: String?, verdict: RefreshVerdict) {
    #expect(RequestPolicy.refreshVerdict(status: status, reason: reason) == verdict)
}

@Test func refreshBackoffEscalatesAndCaps() {
    #expect((1...6).map { RequestPolicy.refreshBackoff(afterFailures: $0) } == [2, 5, 15, 30, 30, 30])
    #expect(RequestPolicy.refreshBackoff(afterFailures: 0) == 2)
}

@Test func pageSizeClampsToServerRange() {
    #expect(PageSize.standard == 20); #expect(PageSize.maximum == 1_000)
    #expect(PageSize.clamped(5_000) == 1_000); #expect(PageSize.clamped(0) == 1); #expect(PageSize.clamped(-3) == 1); #expect(PageSize.clamped(200) == 200)
    let query = [URLQueryItem(name: "page", value: "2"), URLQueryItem(name: "page_size", value: "5000"), URLQueryItem(name: "search", value: "a b")]
    #expect(RequestPolicy.sanitizedQuery(query) == [URLQueryItem(name: "page", value: "2"), URLQueryItem(name: "page_size", value: "1000"),
                                                     URLQueryItem(name: "search", value: "a b")])
    let normal = [URLQueryItem(name: "page_size", value: "500")]
    #expect(RequestPolicy.sanitizedQuery(normal) == normal)
}

@Test func apiResponseLowercasesHeaderNames() {
    let response = APIResponse(value: 3, status: 201, headers: ["X-Request-ID": "rid", "ETag": "\"e1\""])
    #expect(response.status == 201); #expect(response.value == 3)
    #expect(response.header("x-request-id") == "rid"); #expect(response.header("X-Request-ID") == "rid"); #expect(response.requestID == "rid")
    #expect(Set(response.headers.keys) == ["x-request-id", "etag"])
    let mapped = response.map { "\($0)" }
    #expect(mapped.value == "3"); #expect(mapped.status == 201); #expect(mapped.headers == response.headers)
}
