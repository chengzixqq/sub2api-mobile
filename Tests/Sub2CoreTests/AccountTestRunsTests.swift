import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// C08 (accounts.test_runs): start, latest and one run; 20 §0.5 reasons.

private func runJSON(status: String = "running") -> String {
    #"{"run_id":"tr_0190abc","account_id":9,"source":"async","status":"\#(status)","model":"m","latency_ms":null,"#
        + #""first_token_ms":null,"upstream_status_code":null,"error_kind":null,"error_summary":"","error_message":"","#
        + #""response_text":"","recovery":null,"started_at":"2026-10-17T09:40:00Z","finished_at":null}"#
}
private func runsClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), deviceID: stubDeviceID, transport: transport, requestClock: .immediate)
}
private func bodyText(_ request: URLRequest?) -> String { String(decoding: request?.httpBody ?? Data(), as: UTF8.self) }
private func decodedRun(_ json: String) throws -> AccountTestRun { try JSONDecoder().decode(AccountTestRun.self, from: Data(json.utf8)) }

@Test func startTestRunPostsModelAndRecoverFlagAndDecodes202() async throws {
    let transport = ScriptedTransport { _ in okReply(runJSON(), status: 202) }
    let client = runsClient(transport)
    let start = try await client.startTestRun(accountID: 9, modelID: "m")
    guard case .started(let run) = start else { Issue.record("Expected a started run"); return }
    #expect(run.runID == "tr_0190abc" && run.accountID == 9 && run.status == .running && !run.isFinished)
    #expect(run.startedAt == ServerTime.parseTimestamp("2026-10-17T09:40:00Z")); #expect(run.finishedAt == nil)
    let sent = try #require(await transport.requests.first)
    #expect(sent.httpMethod == "POST"); #expect(sent.url?.path == "/api/v1/admin/accounts/9/test-runs")
    #expect(bodyText(sent) == #"{"model_id":"m","recover_on_success":true}"#)
    #expect(sentHeader(sent, "Idempotency-Key") == nil); #expect(sentHeader(sent, "X-Request-ID") != nil)
    _ = try await client.startTestRun(accountID: 9, modelID: nil)
    _ = try await client.startTestRun(accountID: 9, modelID: " ", recoverOnSuccess: false)
    let bodies = await transport.requests.dropFirst().map { bodyText($0) }
    #expect(bodies == [#"{"model_id":"","recover_on_success":true}"#, #"{"model_id":"","recover_on_success":false}"#])
}

@Test func startTestRunRunningConflictReturnsExistingRunID() async throws {
    let transport = ScriptedTransport { _ in errorReply(409, reason: "ACCOUNT_TEST_RUNNING", extra: #","metadata":{"run_id":"tr_0190abc"}"#) }
    #expect(try await runsClient(transport).startTestRun(accountID: 9, modelID: nil) == .alreadyRunning(runID: "tr_0190abc"))
    #expect(await transport.requests.count == 1)
}

@Test(arguments: ["", #","metadata":{"run_id":""}"#, #","metadata":{"run_id":"../x"}"#,
                  #","metadata":{"run_id":"tr_\#(String(repeating: "a", count: 38))"}"#])
func startTestRunConflictWithoutUsableRunIDThrows(_ extra: String) async throws {
    let transport = ScriptedTransport { _ in errorReply(409, reason: "ACCOUNT_TEST_RUNNING", extra: extra) }
    let error = await thrownAPIError { _ = try await runsClient(transport).startTestRun(accountID: 9, modelID: nil) }
    #expect(error?.reason == "ACCOUNT_TEST_RUNNING"); #expect(error?.kind == .conflict)
}

@Test func startTestRunBusyIsNotRetriedAndCarriesRetryAfter() async throws {
    for (headers, seconds) in [(["Retry-After": "12"], 12), ([:], RetryAfter.rateLimitDefault)] as [([String: String], Int)] {
        let transport = ScriptedTransport { _ in errorReply(429, reason: "ACCOUNT_TEST_BUSY", headers: headers) }
        let error = try #require(await thrownAPIError { _ = try await runsClient(transport).startTestRun(accountID: 9, modelID: "m") })
        #expect(error.kind == .rateLimited && error.reason == "ACCOUNT_TEST_BUSY" && error.retryAfter == seconds)
        #expect(error.localizedDescription == "站点同时运行的测试已满，请稍后再试")
        #expect(await transport.requests.count == 1)
    }
}

@Test func latestTestRunMissingIsNil() async throws {
    let missing = ScriptedTransport { _ in errorReply(404, reason: "ACCOUNT_TEST_RUN_NOT_FOUND") }
    #expect(try await runsClient(missing).latestTestRun(accountID: 9) == nil)
    let sent = await missing.requests.first
    #expect(sent?.httpMethod == "GET"); #expect(sent?.url?.path == "/api/v1/admin/accounts/9/test-runs/latest")
    let found = ScriptedTransport { _ in okReply(runJSON(status: "failed").replacingOccurrences(of: "\"async\"", with: "\"manual\"")) }
    let run = try #require(try await runsClient(found).latestTestRun(accountID: 9))
    #expect(run.source == "manual" && run.status == .failed && run.isFinished)
}

@Test func latestTestRunOtherFailuresThrow() async throws {
    let noRoute = ScriptedTransport { _ in HTTPResponse(statusCode: 404, headers: ["content-type": "text/plain"], data: Data("404 page not found".utf8)) }
    #expect(await thrownAPIError { _ = try await runsClient(noRoute).latestTestRun(accountID: 9) }?.kind == .unsupported)
    let noAccount = ScriptedTransport { _ in errorReply(404, reason: "ACCOUNT_NOT_FOUND") }
    #expect(await thrownAPIError { _ = try await runsClient(noAccount).latestTestRun(accountID: 9) }?.kind == .notFound)
}

@Test func testRunDecodesViewAndOnlyExposesSanitizedText() async throws {
    let leaked = "Bearer abc.def sk-ant-api03-xyzxyz https://api.example.invalid/v1"
    let json = runJSON(status: "failed").replacingOccurrences(of: #""latency_ms":null"#, with: #""latency_ms":3420"#)
        .replacingOccurrences(of: #""upstream_status_code":null"#, with: #""upstream_status_code":401"#)
        .replacingOccurrences(of: #""error_kind":null"#, with: #""error_kind":"auth""#)
        .replacingOccurrences(of: #""error_message":"""#, with: #""error_message":"\#(leaked)""#)
        .replacingOccurrences(of: #""response_text":"""#, with: #""response_text":"ok \#(leaked)""#)
        .replacingOccurrences(of: #""finished_at":null"#, with: #""finished_at":"2026-10-17T09:40:03Z""#)
    let transport = ScriptedTransport { _ in okReply(json) }
    let run = try await runsClient(transport).testRun(runID: "tr_0190abc")
    #expect(await transport.requests.first?.url?.path == "/api/v1/admin/account-test-runs/tr_0190abc")
    #expect(run.model == "m" && run.latencyMs == 3420 && run.firstTokenMs == nil && run.upstreamStatusCode == 401)
    #expect(run.errorKind == "auth" && run.errorSummary == nil && run.recovery == nil)
    #expect(run.finishedAt == ServerTime.parseTimestamp("2026-10-17T09:40:03Z"))
    #expect(run.sanitizedErrorText == "[已隐藏] [已隐藏] [已隐藏]")
    #expect(run.sanitizedResponseText == "ok [已隐藏] [已隐藏] [已隐藏]")
    #expect(try decodedRun(runJSON()).sanitizedErrorText == nil)
    let summarized = try decodedRun(runJSON(status: "failed").replacingOccurrences(of: #""error_summary":"""#, with: #""error_summary":"上游限流""#))
    #expect(summarized.errorSummary == "上游限流")
}

@Test(arguments: [("running", AccountTestRun.Status.running), ("success", .success), ("failed", .failed),
                  ("interrupted", .interrupted), ("queued", .unknown)])
func runStatusDecodesKnownAndUnknownValues(_ raw: String, _ status: AccountTestRun.Status) throws {
    let run = try decodedRun(runJSON(status: raw))
    #expect(run.status == status); #expect(run.isFinished == (status != .running))
}

@Test func runStatusMissingIsUnknown() throws {
    let json = runJSON().replacingOccurrences(of: #""status":"running","#, with: "")
    #expect(try decodedRun(json).status == .unknown)
}

@Test(arguments: ["", "abc", "tr_", "tr_../x", "tr_a/b", "tr_a?b", "tr_" + String(repeating: "a", count: 38)])
func testRunRejectsMalformedRunIDLocally(_ runID: String) async throws {
    let transport = ScriptedTransport { _ in okReply(runJSON()) }
    let error = await thrownAPIError { _ = try await runsClient(transport).testRun(runID: runID) }
    #expect(error?.kind == .validation)
    #expect(await transport.requests.isEmpty)
    #expect(!AccountTestRun.isValidRunID(runID))
}

@Test func runIDValidationFollowsTheBackend() {
    #expect(AccountTestRun.isValidRunID("tr_0190abcDEF_1"))
    #expect(AccountTestRun.isValidRunID("tr_" + String(repeating: "a", count: 37)))
    #expect(!AccountTestRun.isValidRunID("TR_0190abc"))
}
