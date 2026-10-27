import Foundation
import Testing
@testable import Sub2Core

// 20 §4.3 result wording, §7.3 reasons, §4.4 interruption check, C07 fallback, output redaction (S2D1-01).

private typealias Presentation = AccountTestPresentation
private typealias State = AccountTestResult.AccountState
private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func state(_ status: String = "active", schedulable: Bool = true, rateLimit: Date? = nil, temp: Date? = nil,
                   summary: String? = nil, kind: String? = nil) -> State {
    State(status: status, schedulable: schedulable, rateLimitResetAt: rateLimit, tempUnschedulableUntil: temp, errorSummary: summary, errorKind: kind)
}
private func failed(status: Int? = nil, kind: String? = nil, account: State? = nil, marked: AccountTestResult.Marked? = nil) -> AccountTestOutcome {
    AccountTestOutcome(passed: false, upstreamStatus: status, account: account, marked: marked, errorKind: kind)
}
private func passed(recovery: AccountTestResult.Recovery? = nil, account: State? = nil, usage: AccountTestResult.Usage? = nil) -> AccountTestOutcome {
    AccountTestOutcome(passed: true, timing: AccountTestTiming(firstTokenMs: 1210, totalMs: 3420, isLocal: false), usage: usage,
                       account: account, recovery: recovery)
}
private func marked(error: Bool = false, rateLimited: Bool = false, temp: Bool = false) -> AccountTestResult.Marked {
    AccountTestResult.Marked(error: error, rateLimited: rateLimited, tempUnschedulable: temp)
}
private func run(_ status: AccountTestRun.Status, startedAt: Date?, latency: Int? = 3420, first: Int? = 1210, upstream: Int? = nil,
                 kind: String? = nil, message: String? = nil) -> AccountTestRun {
    AccountTestRun(runID: "tr_0190abc", accountID: 9, source: "manual", status: status, model: "m", latencyMs: latency, firstTokenMs: first,
                   upstreamStatusCode: upstream, errorKind: kind, startedAt: startedAt, errorMessage: message)
}
private func content(_ text: String) -> AccountTestEvent { AccountTestEvent(type: "content", content: text) }

// MARK: - Default model and header

@Test(arguments: [
    (["claude-opus-4-1", "claude-sonnet-4-5-20250929", "claude-sonnet-4"], "claude-sonnet-4-5-20250929"),
    (["gpt-5.4", "gpt-4.1"], "gpt-5.4"),
    ([], nil),
] as [([String], String?)])
func defaultModelPrefersFirstSonnet(_ ids: [String], _ expected: String?) {
    #expect(Presentation.defaultModel(among: ids) == expected)
}

@Test func headerLinesNameTheTargetAndModel() {
    #expect(Presentation.headerLines(platformName: "Anthropic", accountName: "acc-1", model: nil) == ["→ 测试 Anthropic · acc-1", "→ 模型 默认模型"])
    #expect(Presentation.headerLines(platformName: "OpenAI", accountName: "主号", model: "gpt-5.4")[1] == "→ 模型 gpt-5.4")
    #expect(Presentation.headerLines(platformName: "OpenAI", accountName: "主号", model: " ")[1] == "→ 模型 默认模型")
}

// MARK: - Redaction and transcript

@Test(arguments: [
    ("Authorization: Bearer abc.def", "Authorization: [已隐藏]"),
    ("key sk-ant-api03-abcdef", "key [已隐藏]"),
    ("sk-abc", "sk-abc"),
    ("see HTTPS://api.example.com/v1?x=1 now", "see [已隐藏] now"),
    ("你好🌍 done", "你好🌍 done"),
])
func sanitizeHidesBearerKeysAndURLs(_ raw: String, _ expected: String) {
    #expect(AccountTestOutput.sanitize(raw) == expected)
}

@Test func sanitizeCapsLineLength() {
    #expect(AccountTestOutput.sanitize(String(repeating: "a", count: 9_000)).count == AccountTestOutput.maxLineLength)
}

@Test func transcriptJoinsChunksBeforeSanitizing() {
    let start = ContinuousClock.now
    var transcript = AccountTestTranscript(startedAt: start)
    transcript.apply(content("key sk-ab"), at: start)
    transcript.apply(content("cdef123456\r\nnext"), at: start)
    #expect(transcript.lines == ["key [已隐藏]"]); #expect(transcript.displayLines == ["key [已隐藏]", "next"])
    transcript.apply(AccountTestEvent(type: "status", content: "Retrying https://example.invalid"), at: start)
    #expect(transcript.lines == ["key [已隐藏]", "next", "Retrying [已隐藏]"])
    transcript.apply(AccountTestEvent(type: "error", message: "Bearer x"), at: start)
    #expect(transcript.errorText == "[已隐藏]"); #expect(transcript.lines.last == "✕ [已隐藏]")
    for type in ["image", "audio", "video"] { transcript.apply(AccountTestEvent(type: type), at: start) }
    #expect(transcript.lines.suffix(3) == ["← 收到图片", "← 收到音频", "← 收到视频"])
    transcript.apply(content("tail"), at: start)
    #expect(transcript.lines.last == "← 收到视频"); #expect(transcript.displayLines.last == "tail")
    transcript.finish(at: start)
    #expect(transcript.lines.last == "tail"); #expect(transcript.lineCount == 8)
}

@Test func transcriptKeepsLatest500LinesAndCountsAll() {
    let start = ContinuousClock.now
    var transcript = AccountTestTranscript(startedAt: start)
    transcript.apply(content((1...600).map { "line \($0)\n" }.joined()), at: start)
    #expect(transcript.lines.count == AccountTestOutput.maxLines); #expect(transcript.lines.first == "line 101")
    #expect(transcript.lineCount == 600)
    var long = AccountTestTranscript(startedAt: start)
    long.apply(content(String(repeating: "a", count: 9_000)), at: start)
    #expect(long.lines.map(\.count) == [AccountTestOutput.maxLineLength]); #expect(long.displayLines.last?.count == 808)
}

@Test func transcriptRecordsModelConclusionAndLocalTiming() {
    let start = ContinuousClock.now
    var transcript = AccountTestTranscript(startedAt: start)
    #expect(transcript.legacyPassed == nil && transcript.localTiming == nil)
    transcript.apply(AccountTestEvent(type: "test_start", model: "m"), at: start + .milliseconds(100))
    transcript.apply(content("hi"), at: start + .milliseconds(1_210))
    transcript.apply(AccountTestEvent(type: "test_complete", success: true), at: start + .milliseconds(3_420))
    transcript.finish(at: start + .milliseconds(5_000))
    #expect(transcript.model == "m"); #expect(transcript.completion == true); #expect(transcript.legacyPassed == true)
    #expect(transcript.localTiming == AccountTestTiming(firstTokenMs: 1_210, totalMs: 3_420, isLocal: true))
    #expect(transcript.serverOutcome == nil && !transcript.receivedTestResult)

    var failing = AccountTestTranscript(startedAt: start)
    failing.apply(AccountTestEvent(type: "error", message: "upstream failed"), at: start + .milliseconds(800))
    #expect(failing.legacyPassed == false); #expect(failing.localTiming == AccountTestTiming(firstTokenMs: nil, totalMs: 800, isLocal: true))
    let result = AccountTestResult(success: false, totalMs: 900, upstreamStatus: 401)
    failing.apply(AccountTestEvent(type: "test_result", data: result), at: start + .milliseconds(900))
    #expect(failing.receivedTestResult); #expect(failing.result == result)
    #expect(failing.serverOutcome?.passed == false); #expect(failing.serverOutcome?.errorText == "upstream failed")
    #expect(failing.serverOutcome?.timing == AccountTestTiming(firstTokenMs: nil, totalMs: 900, isLocal: false))

    var silent = AccountTestTranscript(startedAt: start)
    silent.finish(at: start + .milliseconds(500))
    #expect(silent.localTiming == AccountTestTiming(firstTokenMs: nil, totalMs: 500, isLocal: true))
}

// MARK: - 20 §4.3

@Test(arguments: [
    (passed(), "测试通过 · 首字 1.2s · 总耗时 3.4s"),
    (AccountTestOutcome(passed: true, timing: AccountTestTiming(firstTokenMs: nil, totalMs: 3_420, isLocal: false)), "测试通过 · 总耗时 3.4s"),
    (AccountTestOutcome(passed: true, timing: AccountTestTiming(firstTokenMs: 1_210, totalMs: 3_420, isLocal: true)), "测试通过 · 首字 1.2s · 总耗时 3.4s · 本机计时"),
    (AccountTestOutcome(passed: true, timing: AccountTestTiming(firstTokenMs: nil, totalMs: 182_000, isLocal: false)), "测试通过 · 总耗时 182s"),
    (AccountTestOutcome(passed: true), "测试通过"),
    (failed(status: 401), "测试未通过 · 401"),
    (failed(), "测试未通过"),
])
func headlineForPassAndFail(_ outcome: AccountTestOutcome, _ expected: String) {
    #expect(Presentation.headline(outcome) == expected)
}

@Test(arguments: [
    (passed(recovery: .init(clearedError: true, clearedRateLimit: false), account: state(schedulable: true)),
     AccountTestRecoveryNote(text: "已自动清除错误，账号恢复调度", offersEnableScheduling: false)),
    (passed(recovery: .init(clearedError: false, clearedRateLimit: true), account: state(schedulable: false)),
     AccountTestRecoveryNote(text: "已自动清除限流，仍暂停调度", offersEnableScheduling: true)),
    (passed(recovery: .init(clearedError: true, clearedRateLimit: true), account: state(schedulable: true)),
     AccountTestRecoveryNote(text: "已自动清除错误和限流，账号恢复调度", offersEnableScheduling: false)),
    (passed(recovery: .init(clearedError: false, clearedRateLimit: false), account: state()), nil),
    (passed(recovery: .init(clearedError: true, clearedRateLimit: false)), AccountTestRecoveryNote(text: "已自动清除错误", offersEnableScheduling: false)),
    (passed(), nil),
    (AccountTestOutcome(passed: false, recovery: .init(clearedError: true, clearedRateLimit: false)), nil),
] as [(AccountTestOutcome, AccountTestRecoveryNote?)])
func recoveryNoteTable(_ outcome: AccountTestOutcome, _ expected: AccountTestRecoveryNote?) {
    #expect(Presentation.recoveryNote(outcome) == expected)
}

@Test(arguments: [
    (failed(kind: "auth", account: state("error", schedulable: false), marked: marked(error: true)), Presentation.CredentialKind.token,
     "令牌无效，账号保持错误。重新授权后再测试连接"),
    (failed(status: 403, account: state("error", schedulable: false)), .apiKey, "凭据无效，账号保持错误。更换 API Key 后再测试连接"),
    (failed(status: 403, kind: "forbidden", account: state("error"), marked: marked(error: true)), .bedrock, "凭据无效，账号保持错误。在 Web 中更换凭据后再测试连接"),
    (failed(kind: "auth", account: state("error")), .vertex, "凭据无效，账号保持错误。在 Web 中更换凭据后再测试连接"),
    (failed(kind: "quota", account: state("error"), marked: marked(error: true)), .token, "后端已把账号标为“错误”，并停止调度，不会接收请求"),
    (failed(status: 429, account: state(), marked: marked(rateLimited: true)), .apiKey, "测试触发了上游限流，账号进入限流中"),
    (failed(account: state(), marked: marked(temp: true)), .apiKey, "测试触发了临时不可调度"),
    (failed(status: 500, account: state(), marked: marked()), .apiKey, "账号状态没有改变，可以稍后重试"),
    (failed(status: 500, account: state()), .apiKey, "账号状态没有改变，可以稍后重试"),
    (failed(status: 401), .apiKey, nil),
    (passed(account: state()), .apiKey, nil),
] as [(AccountTestOutcome, Presentation.CredentialKind, String?)])
func failureNoteTable(_ outcome: AccountTestOutcome, _ credential: AccountTestPresentation.CredentialKind, _ expected: String?) {
    #expect(Presentation.failureNote(outcome, credential: credential) == expected)
}

@Test func usageTextOnlyForPassedWithUsage() {
    #expect(Presentation.usageText(passed(usage: .init(inputTokens: 1_234, outputTokens: 56))) == "输入 1,234 · 输出 56 tokens")
    #expect(Presentation.usageText(passed()) == nil)
    #expect(Presentation.usageText(AccountTestOutcome(passed: false, usage: .init(inputTokens: 1, outputTokens: 1))) == nil)
}

// MARK: - 20 §7.3

@Test(arguments: [
    ("auth", nil, Presentation.CredentialKind.apiKey, "API Key 无效或已撤销"),
    ("auth", nil, .token, "令牌无效或已撤销"),
    (nil, 401, .token, "令牌无效或已撤销"),
    ("token_refresh", nil, .token, "令牌无效或已撤销"),
    ("forbidden", 403, .token, "授权的账号没有可用额度或权限"),
    ("forbidden", nil, .vertex, "Service Account 没有 Vertex AI 权限"),
    (nil, 403, .bedrock, "AWS 凭据无效或没有 Bedrock 权限"),
    ("forbidden", 403, .apiKey, "上游返回 403"),
    ("quota", 429, .token, "上游额度不足"),
    ("rate_limit", nil, .apiKey, "上游限流"),
    (nil, 429, .apiKey, "上游限流"),
    ("other", 500, .apiKey, "上游返回 500"),
    ("custom_code", 418, .apiKey, "上游返回 418"),
    ("stream_timeout", nil, .apiKey, "上游拒绝了这次测试请求"),
    (nil, nil, .token, "上游拒绝了这次测试请求"),
] as [(String?, Int?, Presentation.CredentialKind, String)])
func failureReasonFollows73Mapping(_ kind: String?, _ status: Int?, _ credential: AccountTestPresentation.CredentialKind, _ expected: String) {
    #expect(Presentation.failureReason(errorKind: kind, upstreamStatus: status, credential: credential) == expected)
    #expect(Presentation.failureReasonHeadline(failed(status: status, kind: kind), credential: credential) == "测试未通过 · " + expected)
}

@Test func failureDetailLineCombinesStatusAndSanitizedError() {
    let outcome = { (status: Int?, text: String?) in AccountTestOutcome(passed: false, upstreamStatus: status, errorText: text) }
    #expect(Presentation.failureDetailLine(outcome(401, "API returned 401: sk-ant-xxxxxxxx")) == "上游返回 401 · API returned 401: [已隐藏]")
    #expect(Presentation.failureDetailLine(outcome(nil, "boom")) == "boom")
    #expect(Presentation.failureDetailLine(outcome(502, nil)) == "上游返回 502")
    #expect(Presentation.failureDetailLine(outcome(nil, nil)) == nil)
    #expect(Presentation.failureDetailLine(AccountTestOutcome(passed: true, upstreamStatus: 200)) == nil)
}

// MARK: - C07 fallback

@Test func legacyOutcomeComparesSnapshots() {
    let local = AccountTestTiming(firstTokenMs: nil, totalMs: 900, isLocal: true)
    let recovered = AccountTestOutcome.legacy(passed: true, timing: local, before: state("error", schedulable: true, summary: "凭据无效"),
                                              after: state(), now: now, errorText: nil)
    #expect(recovered.recovery == .init(clearedError: true, clearedRateLimit: false)); #expect(recovered.timing == local)
    #expect(Presentation.recoveryNote(recovered)?.text == "已自动清除错误，账号恢复调度"); #expect(recovered.account == state())
    let unlimited = AccountTestOutcome.legacy(passed: true, timing: local, before: state(rateLimit: now.addingTimeInterval(600)),
                                              after: state(), now: now, errorText: nil)
    #expect(unlimited.recovery == .init(clearedError: false, clearedRateLimit: true))
    let staleLimit = AccountTestOutcome.legacy(passed: true, timing: local, before: state(rateLimit: now.addingTimeInterval(-600)),
                                               after: state(), now: now, errorText: nil)
    #expect(staleLimit.recovery == .init(clearedError: false, clearedRateLimit: false))
    let broke = AccountTestOutcome.legacy(passed: false, timing: local, before: state(), after: state("error", schedulable: false, summary: "凭据无效"),
                                          now: now, errorText: "boom")
    #expect(broke.marked == marked(error: true)); #expect(broke.recovery == nil); #expect(broke.errorText == "boom")
    let rewritten = AccountTestOutcome.legacy(passed: false, timing: local, before: state("error", summary: "旧错误"),
                                              after: state("error", summary: "新错误"), now: now, errorText: nil)
    #expect(rewritten.marked?.error == true)
    let unchanged = AccountTestOutcome.legacy(passed: false, timing: local, before: state("error", summary: "旧错误"),
                                              after: state("error", summary: "旧错误"), now: now, errorText: nil)
    #expect(unchanged.marked == marked())
    let limited = AccountTestOutcome.legacy(passed: false, timing: local, before: state(rateLimit: now), after: state(rateLimit: now.addingTimeInterval(60)),
                                            now: now, errorText: nil)
    #expect(limited.marked == marked(rateLimited: true))
    let paused = AccountTestOutcome.legacy(passed: false, timing: local, before: state(), after: state(temp: now.addingTimeInterval(60)),
                                           now: now, errorText: nil)
    #expect(paused.marked == marked(temp: true))
    let unknown = AccountTestOutcome.legacy(passed: true, timing: local, before: state("error"), after: nil, now: now, errorText: nil)
    #expect(unknown.marked == nil && unknown.recovery == nil && unknown.account == nil && unknown.timing == local)
}

// MARK: - 20 §4.4 interruption check

@Test func interruptionCheckTable() throws {
    #expect(Presentation.interruptionCheck(latest: nil, attemptStartedAt: now) == .interrupted)
    #expect(Presentation.interruptionCheck(latest: run(.success, startedAt: nil), attemptStartedAt: now) == .interrupted)
    #expect(Presentation.interruptionCheck(latest: run(.success, startedAt: now.addingTimeInterval(-60)), attemptStartedAt: now) == .interrupted)
    for offset in [-1.0, 0, 5] {
        guard case .settled(let outcome) = Presentation.interruptionCheck(latest: run(.success, startedAt: now.addingTimeInterval(offset)),
                                                                          attemptStartedAt: now) else {
            Issue.record("Expected a settled check at \(offset)"); continue
        }
        #expect(outcome.passed); #expect(outcome.timing == AccountTestTiming(firstTokenMs: 1_210, totalMs: 3_420, isLocal: false))
    }
    let after = state("error", schedulable: false, kind: "auth")
    let failedRun = run(.failed, startedAt: now, upstream: 401, kind: "auth", message: "invalid sk-ant-api03-abcdef")
    guard case .settled(let outcome) = Presentation.interruptionCheck(latest: failedRun, attemptStartedAt: now, after: after) else {
        Issue.record("Expected a settled failure"); return
    }
    #expect(!outcome.passed && outcome.upstreamStatus == 401 && outcome.errorKind == "auth")
    #expect(outcome.errorText == "invalid [已隐藏]"); #expect(outcome.account == after)
    for status in [AccountTestRun.Status.interrupted, .running, .unknown] {
        #expect(Presentation.interruptionCheck(latest: run(status, startedAt: now), attemptStartedAt: now) == .interrupted)
    }
}

// MARK: - Adapters

@Test(arguments: [("oauth", Presentation.CredentialKind.token), ("setup-token", .token), ("service_account", .vertex), ("bedrock", .bedrock),
                  ("apikey", .apiKey), ("upstream", .apiKey), ("mystery", .apiKey)] as [(String, AccountTestPresentation.CredentialKind)])
func credentialKindFollowsAccountType(_ type: String, _ expected: AccountTestPresentation.CredentialKind) {
    #expect(Presentation.CredentialKind(accountType: type) == expected)
}

@Test func accountStateReadsTheAccountSnapshot() {
    let account = UpstreamAccount(id: 9, name: "主号", platform: "anthropic", type: "oauth", status: "error", schedulable: false,
                                  errorKind: "auth", errorSummary: "", rateLimitResetAt: "2026-10-17T10:00:00Z",
                                  tempUnschedulableUntil: "2026-10-17T10:05:00.5+08:00")
    let snapshot = State(account: account)
    #expect(snapshot.status == "error" && !snapshot.schedulable && snapshot.errorKind == "auth" && snapshot.errorSummary == nil)
    #expect(snapshot.rateLimitResetAt == ServerTime.parseTimestamp("2026-10-17T10:00:00Z"))
    #expect(snapshot.tempUnschedulableUntil == ServerTime.parseTimestamp("2026-10-17T02:05:00.5Z"))
}
