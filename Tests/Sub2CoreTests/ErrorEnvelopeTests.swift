import Foundation
import Testing
@testable import Sub2Core

private func envelope(_ json: String) -> ErrorEnvelope? { ErrorEnvelope.decode(Data(json.utf8)) }

@Test func decodesHandlerEnvelopeWithIntegerCode() throws {
    let value = try #require(envelope(#"{"code":409,"message":"secret","reason":"IDEMPOTENCY_IN_PROGRESS","metadata":{"retry_after":"12"}}"#))
    #expect(value.code == .int(409))
    #expect(value.marker == "IDEMPOTENCY_IN_PROGRESS")
    #expect(value.metadata?["retry_after"] == "12")
    #expect(value.retryAfter == nil)
    #expect(!value.isSuccess)
}

@Test func decodesMiddlewareEnvelopeWithStringCode() throws {
    let value = try #require(envelope(#"{"code":"TOKEN_EXPIRED","message":"Token has expired","reason":"TOKEN_EXPIRED"}"#))
    #expect(value.code == .string("TOKEN_EXPIRED"))
    #expect(value.marker == "TOKEN_EXPIRED")
}

@Test func markerPrefersReasonThenStringCode() throws {
    #expect(envelope(#"{"code":"MIDDLEWARE","reason":"SPECIFIC"}"#)?.marker == "SPECIFIC")
    #expect(envelope(#"{"code":"MIDDLEWARE","reason":"  "}"#)?.marker == "MIDDLEWARE")
    #expect(envelope(#"{"code":400,"message":"Invalid request: x","reason":""}"#)?.marker == nil)
    #expect(envelope(#"{"code":"ONLY_CODE"}"#)?.marker == "ONLY_CODE")
    #expect(envelope(#"{"code":503}"#)?.marker == nil)
}

@Test func decodesComplianceLockedBody() throws {
    let json = #"{"code":"ADMIN_COMPLIANCE_ACK_REQUIRED","reason":"ADMIN_COMPLIANCE_ACK_REQUIRED","message":"ack","metadata":{"version":"2026-10","document_path_zh":"/legal/zh","document_url_zh":"https://docs.example.invalid/zh"}}"#
    let value = try #require(envelope(json))
    #expect(value.marker == "ADMIN_COMPLIANCE_ACK_REQUIRED")
    #expect(value.metadata?["version"] == "2026-10")
    #expect(value.metadata?["document_url_zh"] == "https://docs.example.invalid/zh")
    #expect(value.metadata?["document_path_zh"] == "/legal/zh")
}

@Test func decodesLoginRateLimitWithTopLevelRetryAfter() throws {
    let numeric = try #require(envelope(#"{"code":"RATE_LIMITED","reason":"RATE_LIMITED","retry_after":12,"error":"rate limit exceeded","message":"slow down"}"#))
    #expect(numeric.retryAfter == 12); #expect(numeric.marker == "RATE_LIMITED")
    let text = try #require(envelope(#"{"code":"RATE_LIMITED","reason":"RATE_LIMITED","retry_after":"12"}"#))
    #expect(text.retryAfter == 12)
    #expect(envelope(#"{"code":"RATE_LIMITED","retry_after":-4}"#)?.retryAfter == nil)
}

@Test func nonJSONBodiesYieldNoEnvelope() {
    #expect(ErrorEnvelope.decode(Data("404 page not found".utf8)) == nil)
    #expect(ErrorEnvelope.decode(Data("<html><body><h1>502 Bad Gateway</h1></body></html>".utf8)) == nil)
    #expect(ErrorEnvelope.decode(Data()) == nil)
    #expect(ErrorEnvelope.decode(Data(#"[{"code":0}]"#.utf8)) == nil)
    #expect(ErrorEnvelope.decode(Data("null".utf8)) == nil)
}

@Test func oddFieldTypesDoNotDropReason() throws {
    let mixed = try #require(envelope(#"{"code":409,"reason":"X","metadata":{"count":3,"ratio":1.5,"flag":true,"nested":{"a":"b"},"name":"n"}}"#))
    #expect(mixed.marker == "X")
    #expect(mixed.metadata == ["count": "3", "ratio": "1.5", "flag": "true", "name": "n"])
    let wrongTypes = try #require(envelope(#"{"code":[1],"reason":"KEPT","metadata":"oops","retry_after":{"s":1}}"#))
    #expect(wrongTypes.code == nil); #expect(wrongTypes.marker == "KEPT")
    #expect(wrongTypes.metadata == nil); #expect(wrongTypes.retryAfter == nil)
    let mixedChannel = #"{"code":409,"reason":"MIXED_CHANNEL_WARNING","error":"mixed_channel_warning","message":"Group 'a' mixes","metadata":{"group_id":"7","group_name":"a","current_platform":"Antigravity","other_platform":"Anthropic"},"details":{"group_id":7,"group_name":"a"}}"#
    let channel = try #require(envelope(mixedChannel))
    #expect(channel.marker == "MIXED_CHANNEL_WARNING"); #expect(channel.metadata?["group_id"] == "7")
}

@Test func successCodeIsOnlyIntegerZero() {
    #expect(envelope(#"{"code":0,"message":"success","data":{}}"#)?.isSuccess == true)
    #expect(envelope(#"{"code":"0"}"#)?.isSuccess == false)
    #expect(envelope(#"{"message":"success"}"#)?.isSuccess == false)
}

@Test func retryAfterResolutionOrder() {
    let full = ErrorEnvelope(code: .int(429), reason: "RATE_LIMITED", metadata: ["retry_after": "20"], retryAfter: 12)
    #expect(RetryAfter.resolve(headers: ["retry-after": "7"], envelope: full) == 7)
    #expect(RetryAfter.resolve(headers: [:], envelope: full) == 12)
    #expect(RetryAfter.resolve(headers: [:], envelope: ErrorEnvelope(metadata: ["retry_after": "20"])) == 20)
    #expect(RetryAfter.resolve(headers: [:], envelope: ErrorEnvelope(reason: "X")) == nil)
    #expect(RetryAfter.resolve(headers: [:], envelope: nil) == nil)
    #expect(RetryAfter.resolve(headers: ["retry-after": "soon"], envelope: full) == 12)
    #expect(RetryAfter.resolve(headers: ["Retry-After": " 9 "], envelope: nil) == 9)
    #expect(RetryAfter.seconds("-3") == nil); #expect(RetryAfter.seconds("1.5") == nil); #expect(RetryAfter.seconds(nil) == nil)
    #expect(RetryAfter.seconds("0") == 0); #expect(RetryAfter.rateLimitDefault == 30)
}

@Test func responseHeaderLookupIgnoresCase() {
    let response = HTTPResponse(statusCode: 200, headers: ["x-request-id": "req-fixture-0", "Retry-After": "5"], data: Data())
    #expect(response.header("X-Request-ID") == "req-fixture-0")
    #expect(response.header("retry-after") == "5")
    #expect(response.header("ETag") == nil)
}
