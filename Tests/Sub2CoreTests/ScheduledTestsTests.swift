import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Sub2Core

// 20 §9 定时测试（只读, S2-21）: the bare-array reads (S2D1-15), the combined read and the row / result wording.

private func scheduledClient(_ transport: ScriptedTransport) -> APIClient {
    APIClient(server: stubServer(), credential: .adminKey("fixture-admin-key"), deviceID: stubDeviceID, transport: transport, requestClock: .immediate)
}
private func bare(_ json: String, status: Int = 200) -> HTTPResponse { HTTPResponse(statusCode: status, headers: [:], data: Data(json.utf8)) }
private func plan(_ id: Int, cron: String? = "*/10 * * * *", model: String? = "claude-sonnet-4-5", enabled: Bool = true) -> ScheduledTestPlan {
    ScheduledTestPlan(id: id, modelID: model, cronExpression: cron, enabled: enabled)
}
private func result(_ id: Int, _ status: ScheduledTestResult.Status?, latency: Int? = nil, at: String? = "2026-10-24T01:40:00Z", code: Int? = nil,
                    kind: String? = nil, message: String? = nil) -> ScheduledTestResult {
    ScheduledTestResult(id: id, status: status, latencyMs: latency, startedAt: ServerTime.parseTimestamp(at), upstreamStatusCode: code,
                        errorKind: kind, errorMessage: message)
}
private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private let utc = TimeZone(identifier: "UTC")!

// MARK: - Decoding and requests

@Test func plansDecodeWithMissingFieldsAndNull() async throws {
    let body = #"[{"id":30,"account_id":7,"cron_expression":"*/10 * * * *","last_run_at":null},{"model_id":"no-id"},"#
        + #"{"id":31,"model_id":"m","enabled":true,"next_run_at":"2026-10-24T01:50:00Z","max_results":"x"}]"#
    let plans = try await scheduledClient(ScriptedTransport { _ in bare(body) }).scheduledTestPlans(accountID: 7)
    #expect(plans == [ScheduledTestPlan(id: 30, cronExpression: "*/10 * * * *"), ScheduledTestPlan(id: 31, modelID: "m", enabled: true)])
    for empty in ["null", "[]", " null "] {
        #expect(try await scheduledClient(ScriptedTransport { _ in bare(empty) }).scheduledTestPlans(accountID: 7).isEmpty, "\(empty)")
    }
    for broken in [#"{"items":[]}"#, #""text""#, "[1", ""] {
        let error = await thrownAPIError { _ = try await scheduledClient(ScriptedTransport { _ in bare(broken) }).scheduledTestPlans(accountID: 7) }
        #expect(error == .invalidResponse, "\(broken)")
    }
}

@Test func resultsDecodeEveryFieldLeniently() async throws {
    let body = #"[{"id":5,"plan_id":31,"status":"failed","latency_ms":400,"started_at":"2026-10-24T01:40:00.123456Z","#
        + #""upstream_status_code":429,"error_kind":"rate_limit","error_message":"API returned 429: slow down","response_text":"secret"},"#
        + #"{"id":6,"status":"success","latency_ms":"fast","started_at":"bad","upstream_status_code":null,"error_kind":null},"#
        + #"{"id":7,"status":"queued"},{"status":"success"}]"#
    let results = try await scheduledClient(ScriptedTransport { _ in bare(body) }).scheduledTestResults(planID: 31)
    #expect(results.map(\.id) == [5, 6, 7])
    #expect(results[0].status == .failed && results[0].latencyMs == 400 && results[0].upstreamStatusCode == 429 && results[0].errorKind == "rate_limit")
    #expect(results[0].startedAt == ServerTime.parseTimestamp("2026-10-24T01:40:00.123456Z") && results[0].startedAt != nil)
    #expect(results[1].status == .success && results[1].latencyMs == nil && results[1].startedAt == nil && results[1].upstreamStatusCode == nil)
    #expect(results[2].status == .other("queued"))
}

@Test func requestsUseRawArrayEndpoints() async throws {
    let transport = ScriptedTransport { _ in bare("[]") }
    let client = scheduledClient(transport)
    _ = try await client.scheduledTestPlans(accountID: 7)
    _ = try await client.scheduledTestResults(planID: 31)
    _ = try await client.scheduledTestResults(planID: 31, limit: 0)
    _ = try await client.scheduledTestResults(planID: 31, limit: 99)
    let sent = await transport.requests
    #expect(sent.map(\.httpMethod) == ["GET", "GET", "GET", "GET"])
    #expect(sent.first?.url?.path == "/api/v1/admin/accounts/7/scheduled-test-plans")
    #expect(sent.dropFirst().map { $0.url?.path } == Array(repeating: "/api/v1/admin/scheduled-test-plans/31/results", count: 3))
    #expect(sent.dropFirst().map { $0.url?.query } == ["limit=20", "limit=1", "limit=50"])
    let invalid = await thrownAPIError { _ = try await client.scheduledTestPlans(accountID: 0) }
    #expect(invalid?.kind == .validation)
}

@Test func envelopeBodiesStillDecodeAndErrorsKeepTheirReason() async throws {
    let wrapped = try await scheduledClient(ScriptedTransport { _ in okReply(#"[{"id":31,"enabled":true}]"#) }).scheduledTestPlans(accountID: 7)
    #expect(wrapped == [ScheduledTestPlan(id: 31, enabled: true)])
    let missing = await thrownAPIError {
        _ = try await scheduledClient(ScriptedTransport { _ in errorReply(404, reason: "ACCOUNT_NOT_FOUND") }).scheduledTestPlans(accountID: 7)
    }
    #expect(missing?.reason == "ACCOUNT_NOT_FOUND" && missing?.statusCode == 404)
    let refused = await thrownAPIError {
        _ = try await scheduledClient(ScriptedTransport { _ in bare(#"{"code":7,"reason":"SOMETHING"}"#) }).scheduledTestPlans(accountID: 7)
    }
    #expect(refused?.statusCode == 500 && refused?.reason == "SOMETHING")
    // An ordinary enveloped read is untouched by the bare branch.
    let stats = try await scheduledClient(ScriptedTransport { _ in okReply(#"{"requests":3,"tokens":10,"cost":0.5}"#) }).accountTodayStats(id: 7)
    #expect(stats.requests == 3)
}

@Test func snapshotReadsOnlyPrimaryPlanResults() async throws {
    func run(_ plans: String, results: HTTPResponse = bare(#"[{"id":1,"status":"success"}]"#)) async throws -> (AccountScheduledTestsSnapshot, [String]) {
        let transport = ScriptedTransport { request in request.url?.path.hasSuffix("/scheduled-test-plans") == true ? bare(plans) : results }
        let snapshot = try await scheduledClient(transport).accountScheduledTests(accountID: 7, resultLimit: 1)
        return (snapshot, await transport.requests.compactMap { $0.url.map { $0.path + "?" + ($0.query ?? "") } })
    }
    let (mixed, mixedPaths) = try await run(#"[{"id":30,"enabled":false},{"id":31,"enabled":true},{"id":32,"enabled":true}]"#)
    #expect(mixed.primaryPlan?.id == 31 && mixed.plans.map(\.id) == [30, 31, 32])
    #expect(mixed.results == .loaded([ScheduledTestResult(id: 1, status: .success)]))
    #expect(mixedPaths == ["/api/v1/admin/accounts/7/scheduled-test-plans?", "/api/v1/admin/scheduled-test-plans/31/results?limit=1"])
    let (disabled, disabledPaths) = try await run(#"[{"id":30,"enabled":false},{"id":33}]"#)
    #expect(disabled.primaryPlan?.id == 30 && disabledPaths.last == "/api/v1/admin/scheduled-test-plans/30/results?limit=1")
    let (none, nonePaths) = try await run("null")
    #expect(none.plans.isEmpty && none.primaryPlan == nil && none.results == .notRequested && nonePaths.count == 1)
    // The vendor route guard's body (middleware.AbortWithError): a string code, no reason.
    let forbidden = HTTPResponse(statusCode: 403, headers: [:], data: Data(#"{"code":"FORBIDDEN","message":"vendor route"}"#.utf8))
    let (hidden, _) = try await run(#"[{"id":31,"enabled":true}]"#, results: forbidden)
    #expect(hidden.results == .unavailable && hidden.primaryPlan?.id == 31)
    let failed = await thrownAPIError { _ = try await run(#"[{"id":31,"enabled":true}]"#, results: errorReply(500, reason: "INTERNAL")) }
    #expect(failed?.statusCode == 500)
    let denied = await thrownAPIError { _ = try await run(#"[{"id":31,"enabled":true}]"#, results: errorReply(403, reason: "WORKSPACE_PERMISSION_DENIED")) }
    #expect(denied?.reason == "WORKSPACE_PERMISSION_DENIED")
}

// MARK: - Wording

@Test(arguments: [
    ("*/10 * * * *", "每 10 分钟", false), ("0 */2 * * *", "每 2 小时", false), ("  */5   *  * * *  ", "每 5 分钟", false),
    ("*/1 * * * *", "每 1 分钟", false), ("0 */23 * * *", "每 23 小时", false),
    ("*/0 * * * *", "*/0 * * * *", true), ("*/x * * * *", "*/x * * * *", true), ("0 9 * * *", "0 9 * * *", true),
    ("5 */2 * * *", "5 */2 * * *", true), ("* * * * *", "* * * * *", true), ("*/10 * * * * *", "*/10 * * * * *", true),
    ("*/60 * * * *", "*/60 * * * *", true), ("0 */24 * * *", "0 */24 * * *", true), (" 15 9 * * 1-5 ", "15 9 * * 1-5", true)
])
func cronTextTable(_ expression: String, _ text: String, _ isRaw: Bool) {
    let shown = ScheduledTestsPresentation.cronText(expression)
    #expect(shown.text == text && shown.isRaw == isRaw)
}

@Test func cronTextMissingIsDash() {
    for missing in [nil, "", "   "] as [String?] { #expect(ScheduledTestsPresentation.cronText(missing).text == "—") }
}

@Test func summaryTable() {
    func summary(_ plans: [ScheduledTestPlan], _ results: AccountScheduledTestsSnapshot.Results) -> ScheduledTestSummary {
        ScheduledTestsPresentation.summary(AccountScheduledTestsSnapshot(plans: plans, results: results))
    }
    #expect(summary([], .notRequested).text == "没有计划 · 在 Web 中添加")
    #expect(summary([plan(1, enabled: false), plan(2, enabled: false)], .loaded([])).text == "计划已停用")
    let passed = summary([plan(1, enabled: false), plan(2)], .loaded([result(9, .success)]))
    #expect(passed.text == "每 10 分钟 · claude-sonnet-4-5 · 上次成功" && passed.tone == nil)
    let failed = summary([plan(2)], .loaded([result(9, .failed), result(8, .success)]))
    #expect(failed.text == "每 10 分钟 · claude-sonnet-4-5 · 上次失败" && failed.tone == .critical)
    #expect(summary([plan(2, model: "gpt-4.1-mini")], .loaded([])).text == "每 10 分钟 · gpt-4.1-mini")
    #expect(summary([plan(2, model: " ")], .loaded([])).text == "每 10 分钟 · 默认模型")
    #expect(summary([plan(2, model: nil)], .unavailable).text == "每 10 分钟 · 默认模型")
    #expect(summary([plan(2)], .loaded([result(9, .other("queued"))])).text == "每 10 分钟 · claude-sonnet-4-5")
    let raw = summary([plan(2, cron: "15 9 * * 1-5")], .loaded([]))
    #expect(raw == .active(schedule: "15 9 * * 1-5", isRawCron: true, model: "claude-sonnet-4-5", last: nil))
    #expect(raw.monospacedPrefix == "15 9 * * 1-5" && passed.monospacedPrefix == nil)
    #expect(ScheduledTestSummary.readFailed.text == "读取失败" && ScheduledTestSummary.readFailed.tone == nil)
}

@Test func pageNotesForPlans() {
    #expect(ScheduledTestsPresentation.planText(plan(1)) == "每 10 分钟 · claude-sonnet-4-5")
    #expect(ScheduledTestsPresentation.planText(plan(1, cron: "0 */2 * * *", model: "", enabled: false)) == "每 2 小时 · 默认模型 · 已停用")
    #expect(ScheduledTestsPresentation.otherPlansNote(AccountScheduledTestsSnapshot(plans: [plan(1)], results: .loaded([]))) == nil)
    #expect(ScheduledTestsPresentation.otherPlansNote(AccountScheduledTestsSnapshot(plans: [plan(1), plan(2), plan(3)], results: .loaded([])))
        == "另有 2 个计划，在 Web 中查看")
}

@Test func resultRowSuccessAndTime() {
    let passed = result(1, .success, latency: 1_300)
    #expect(ScheduledTestsPresentation.resultRow(passed, timeZone: shanghai).time == "09:40")
    let row = ScheduledTestsPresentation.resultRow(passed, timeZone: utc)
    #expect(row.time == "01:40" && row.id == 1 && row.outcome == .success(latency: "1.3s") && row.text == "成功 · 1.3s")
    #expect(row.spokenText == "01:40，成功 · 1.3s")
    let bare = ScheduledTestsPresentation.resultRow(result(2, .success, latency: nil, at: nil), timeZone: utc)
    #expect(bare.text == "成功" && bare.time == "—" && bare.spokenText == "无数据，成功")
    #expect(ScheduledTestsPresentation.resultRow(result(3, .success, latency: -5), timeZone: utc).text == "成功")
}

@Test func resultRowFailureKindWords() {
    func row(_ code: Int?, _ kind: String?, status: ScheduledTestResult.Status? = .failed) -> ScheduledTestResultRow {
        ScheduledTestsPresentation.resultRow(result(1, status, code: code, kind: kind), timeZone: utc)
    }
    #expect(row(401, "auth").outcome == .failure(badge: "401", tone: .critical, word: "凭据无效"))
    #expect(row(403, "forbidden").text == "403 无权限")
    #expect(row(402, "quota").text == "402 额度不足")
    #expect(row(429, "rate_limit").outcome == .failure(badge: "429", tone: .caution, word: "上游限流"))
    #expect(row(529, "other").text == "529 上游 529")
    #expect(row(500, "stream_timeout").text == "500 上游 500")
    for (code, word) in [(401, "凭据无效"), (402, "额度不足"), (403, "无权限"), (429, "上游限流"), (503, "上游 503")] {
        #expect(row(code, nil).text == "\(code) \(word)", "old server \(code)")
    }
    #expect(row(nil, "custom_code").outcome == .failure(badge: "—", tone: .neutral, word: "失败"))
    #expect(row(nil, nil, status: .other("queued")).text == "— 失败")
    #expect(row(nil, nil, status: nil).spokenText == "01:40，失败")
    #expect(row(401, "auth").spokenText == "01:40，401 凭据无效")
}

@Test func statusCodeRegexFallback() {
    func code(_ message: String?, upstream: Int? = nil) -> Int? {
        ScheduledTestsPresentation.statusCode(of: result(1, .failed, code: upstream, message: message))
    }
    #expect(code("request failed (503)") == 503)
    #expect(code("API returned 429: slow down") == 429)
    #expect(code("upstream returned 529 overloaded") == 529)
    #expect(code("bad (999)") == nil && code("returned 42") == nil && code("HTTP 403") == nil && code(nil) == nil && code("") == nil)
    #expect(code("API returned 429", upstream: 401) == 401)
    #expect(code("API returned 429", upstream: 0) == 429)
    let row = ScheduledTestsPresentation.resultRow(result(1, .failed, kind: "other", message: "no status here"), timeZone: utc)
    #expect(row.outcome == .failure(badge: "—", tone: .neutral, word: "失败"))
    let parsed = ScheduledTestsPresentation.resultRow(result(1, .failed, kind: "other", message: "upstream returned 529 overloaded"), timeZone: utc)
    #expect(parsed.outcome == .failure(badge: "529", tone: .critical, word: "上游 529"))
}

@Test func rowNeverShowsErrorMessage() async throws {
    let message = "API returned 401: invalid_api_key sk-abc123"
    let made = result(1, .failed, kind: "auth", message: message)
    let body = #"[{"id":1,"status":"failed","error_kind":"auth","error_message":"\#(message)","response_text":"sk-response"}]"#
    let decoded = try #require(try await scheduledClient(ScriptedTransport { _ in bare(body) }).scheduledTestResults(planID: 1).first)
    for item in [made, decoded] {
        let row = ScheduledTestsPresentation.resultRow(item, timeZone: utc)
        #expect(row.text == "401 凭据无效")
        for shown in [row.text, row.spokenText, String(describing: item), String(reflecting: item), String(describing: row)] {
            #expect(!shown.contains("invalid_api_key") && !shown.contains("sk-"), "\(shown)")
        }
    }
}

@Test func foregroundReadsAgainWithoutAnAnswer() {
    let snapshot = AccountScheduledTestsSnapshot(plans: [plan(1)], results: .notRequested)
    let at = Date(timeIntervalSince1970: 1_000)
    func reads(_ state: BlockState<AccountScheduledTestsSnapshot>) -> Bool { ScheduledTestsPresentation.readsAgainOnForeground(state) }
    // Going to the background cancels the first read, which leaves the row idle (LoadState.withCancelledLoad).
    #expect(reads(BlockState<AccountScheduledTestsSnapshot>.loading(previous: nil, at: nil).withCancelledLoad()))
    #expect(reads(.idle))
    #expect(reads(.failed(reason: "读取失败", previous: nil, at: nil)))
    #expect(reads(.failed(reason: nil, previous: snapshot, at: at)))
    #expect(!reads(.loaded(snapshot, at: at)))
    #expect(!reads(BlockState.loading(previous: snapshot, at: at).withCancelledLoad()))
    #expect(!reads(.loading(previous: nil, at: nil)))
    #expect(!reads(.disabled(reason: "OPS_DISABLED")))
}
