import Foundation
import Testing
@testable import Sub2Core

// 20 §4.3–§4.5: the test sheet's result area, receipts, start failures and the status fields a test writes back (S2-14).

private typealias Flow = AccountTestFlow
private typealias State = AccountTestResult.AccountState
private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func account(_ type: String = "apikey", status: String = "error", schedulable: Bool = false) -> UpstreamAccount {
    var account = UpstreamAccount(id: 7, name: "主号", platform: "openai", type: type, status: status, schedulable: schedulable,
                                  rateLimitResetAt: ServerTime.utcTimestamp(now.addingTimeInterval(600)))
    account.errorMessage = "401 invalid"; account.errorSummary = "401 invalid"; account.errorKind = "auth"
    account.errorStatusCode = 401; account.errorAt = ServerTime.utcTimestamp(now); account.notes = "备注"; account.groupIDs = [2, 4]
    return account
}
private func passed(recovery: AccountTestResult.Recovery? = nil, schedulable: Bool = true, usage: AccountTestResult.Usage? = nil) -> AccountTestOutcome {
    AccountTestOutcome(passed: true, timing: AccountTestTiming(firstTokenMs: 1210, totalMs: 3420, isLocal: false), usage: usage,
                       account: State(status: "active", schedulable: schedulable), recovery: recovery)
}
private func failed(kind: String? = "auth", status: Int? = 401) -> AccountTestOutcome {
    AccountTestOutcome(passed: false, upstreamStatus: status, account: State(status: "error", schedulable: false, errorKind: kind),
                       marked: AccountTestResult.Marked(error: true, rateLimited: false, tempUnschedulable: false), errorKind: kind)
}
private func api(_ status: Int, _ reason: String?, retryAfter: Int? = nil, security: SecurityPromptOutcome? = nil) -> APIError {
    let base = APIError.server(status: status, reason: reason)
    return APIError(kind: base.kind, reason: reason, statusCode: status, message: base.localizedDescription, retryAfter: retryAfter,
                    securityOutcome: security)
}

// MARK: - Result area

@Test func passedResultOffersEnableSchedulingOnlyWhenStillPaused() {
    let paused = Flow.content(.finished(passed(recovery: .init(clearedError: true, clearedRateLimit: false), schedulable: false,
                                               usage: .init(inputTokens: 12, outputTokens: 128))), credential: .apiKey)
    #expect(paused.title == "测试通过 · 首字 1.2s · 总耗时 3.4s")
    #expect(paused.detail == "已自动清除错误，仍暂停调度")
    #expect(paused.usage == "输入 12 · 输出 128 tokens")
    #expect(paused.tone == .ok && paused.offersEnableScheduling && !paused.offersRetest)
    let live = Flow.content(.finished(passed(recovery: .init(clearedError: true, clearedRateLimit: false))), credential: .apiKey)
    #expect(live.detail == "已自动清除错误，账号恢复调度" && !live.offersEnableScheduling)
    #expect(Flow.content(.finished(passed()), credential: .apiKey).detail == nil)
}

@Test func failedResultExplainsTheNextStepByCredential() {
    let key = Flow.content(.finished(failed()), credential: .apiKey)
    #expect(key.title == "测试未通过 · 401")
    #expect(key.detail == "凭据无效，账号保持错误。更换 API Key 后再测试连接")
    #expect(key.tone == .critical && !key.offersEnableScheduling && !key.offersRetest && key.usage == nil)
    #expect(Flow.content(.finished(failed()), credential: .token).detail == "令牌无效，账号保持错误。重新授权后再测试连接")
}

@Test func interruptedAndNotStartedOfferRetest() {
    let interrupted = Flow.content(.interrupted, credential: .apiKey)
    #expect(interrupted.title == "测试被中断，不能判定是否成功" && interrupted.tone == .caution && interrupted.offersRetest)
    let failed = Flow.content(.notStarted(.failed("站点暂时不可用")), credential: .apiKey)
    #expect(failed.title == "测试没有开始：站点暂时不可用" && failed.offersRetest)
    #expect(Flow.content(.notStarted(.busy(retryAfter: 12)), credential: .apiKey).title == "测试没有开始：站点同时运行的测试已满，请稍后再试")
    let readOnly = Flow.content(.notStarted(.readOnly), credential: .apiKey)
    #expect(readOnly.title == "只读令牌" && !readOnly.offersRetest)
    #expect(readOnly.detail == "当前管理访问令牌只读，不能执行此操作")
}

// MARK: - Receipts (20 §4.4)

@Test func receiptsNameTheAccountAndOfferViewOrRetest() {
    let pass = Flow.receipt(.finished(passed()), name: "主号")
    #expect(pass?.text == "「主号」测试通过" && pass?.tone == .ok && pass?.button == .view && pass?.button?.title == "查看")
    let fail = Flow.receipt(.finished(failed()), name: "主号")
    #expect(fail?.text == "「主号」测试未通过" && fail?.tone == .critical && fail?.button == .view)
    let interrupted = Flow.receipt(.interrupted, name: "主号")
    #expect(interrupted?.text == "测试被中断，不能判定是否成功" && interrupted?.button == .retest && interrupted?.button?.title == "重新测试")
    #expect(Flow.receipt(.notStarted(.failed("x")), name: "主号")?.text == "测试没有开始：x")
    #expect(Flow.receipt(.notStarted(.failed("x")), name: "主号")?.button == .retest)
    #expect(Flow.receipt(.notStarted(.busy(retryAfter: 30)), name: "主号")?.button == nil)
    #expect(Flow.receipt(.notStarted(.readOnly), name: "主号")?.text == "当前管理访问令牌只读，不能执行此操作")
    #expect(Flow.receipt(.notStarted(.cancelled), name: "主号") == nil)
}

@Test func busyRetryCountsDownRetryAfter() {
    let busy = AccountTestEnding.notStarted(.busy(retryAfter: 30))
    #expect(Flow.retryWait(busy, endedAt: now, now: now.addingTimeInterval(0.4)) == 30)
    #expect(Flow.retryWait(busy, endedAt: now, now: now.addingTimeInterval(29.5)) == 1)
    #expect(Flow.retryWait(busy, endedAt: now, now: now.addingTimeInterval(31)) == 0)
    #expect(Flow.retryWait(.interrupted, endedAt: now, now: now) == 0)
    #expect(Flow.retryTitle(remainingSeconds: 12) == "12 秒后重新测试")
    #expect(Flow.retryTitle(remainingSeconds: 0) == "重新测试")
}

// MARK: - Start failures and the vendor fallback

@Test func startFailuresMapWithoutTheServerMessage() {
    #expect(Flow.startFailure(CancellationError()) == .cancelled)
    #expect(Flow.startFailure(api(403, "STEP_UP_REQUIRED", security: .cancelled)) == .cancelled)
    #expect(Flow.startFailure(api(403, "ACCESS_TOKEN_READ_ONLY")) == .readOnly)
    #expect(Flow.startFailure(api(429, "ACCOUNT_TEST_BUSY", retryAfter: 12)) == .busy(retryAfter: 12))
    #expect(Flow.startFailure(api(429, "ACCOUNT_TEST_BUSY")) == .busy(retryAfter: 30))
    let site = Flow.startFailure(APIError.server(status: 500, reason: nil))
    #expect(site == .failed(APIError.server(status: 500, reason: nil).localizedDescription))
    #expect(site.message.hasPrefix("测试没有开始："))
}

@Test func onlyVendorForbiddenFallsBackToStream() {
    #expect(Flow.fallsBackToStream(api(403, "FORBIDDEN")))
    for error in [api(403, "ACCESS_TOKEN_READ_ONLY"), api(403, "STEP_UP_REQUIRED"), api(409, "ACCOUNT_TEST_RUNNING"),
                  api(429, "ACCOUNT_TEST_BUSY"), APIError(kind: .transport, message: "无法连接站点")] {
        #expect(!Flow.fallsBackToStream(error))
    }
    #expect(Flow.isMissingRun(api(404, "ACCOUNT_TEST_RUN_NOT_FOUND")))
    #expect(!Flow.isMissingRun(api(404, "ACCOUNT_NOT_FOUND")))
}

// MARK: - The interruption check's run and the status fields

@Test func onlyAFinishedRunOfThisAttemptConcludes() {
    func run(_ status: AccountTestRun.Status, _ offset: TimeInterval?) -> AccountTestRun {
        AccountTestRun(runID: "tr_1", accountID: 7, status: status, startedAt: offset.map { now.addingTimeInterval($0) })
    }
    #expect(Flow.concludes(run(.success, 0), attemptStartedAt: now))
    #expect(Flow.concludes(run(.interrupted, 1), attemptStartedAt: now))
    #expect(Flow.concludes(run(.failed, -1), attemptStartedAt: now))
    #expect(!Flow.concludes(run(.success, -60), attemptStartedAt: now))
    #expect(!Flow.concludes(run(.running, 1), attemptStartedAt: now))
    #expect(!Flow.concludes(run(.success, nil), attemptStartedAt: now))
    #expect(!Flow.concludes(nil, attemptStartedAt: now))
}

@Test func applyingTestStateWritesOnlyStatusFields() {
    let original = account()
    let cleared = Flow.applying(State(status: "active", schedulable: false, errorSummary: ""), to: original)
    #expect(cleared.status == "active" && !cleared.schedulable && cleared.rateLimitResetAt == nil && cleared.tempUnschedulableUntil == nil)
    #expect(cleared.errorMessage == nil && cleared.errorSummary == nil && cleared.errorKind == nil && cleared.errorStatusCode == nil && cleared.errorAt == nil)
    #expect(cleared.name == "主号" && cleared.notes == "备注" && cleared.groupIDs == [2, 4])
    let limit = now.addingTimeInterval(120)
    let failed = Flow.applying(State(status: "error", schedulable: false, rateLimitResetAt: limit, errorSummary: "x", errorKind: "auth"), to: original)
    #expect(failed.errorKind == "auth" && failed.errorSummary == "x" && failed.errorStatusCode == 401)
    #expect(failed.rateLimitResetAt == ServerTime.utcTimestamp(limit))
    #expect(original.status == "error" && original.errorSummary == "401 invalid")
}

@Test func finishedRunsAddTheirTextToTheOutput() {
    let json = #"{"run_id":"tr_1","account_id":7,"status":"success","response_text":"pong sk-abcdef123456"}"#
    let success = try! JSONDecoder().decode(AccountTestRun.self, from: Data(json.utf8))
    var transcript = AccountTestTranscript(startedAt: .now)
    for event in Flow.outputEvents(for: success) { transcript.apply(event, at: .now) }
    transcript.finish(at: .now)
    #expect(transcript.displayLines == ["pong [已隐藏]"])
    let failed = AccountTestRun(runID: "tr_2", accountID: 7, status: .failed, errorSummary: "401 invalid", errorMessage: "API returned 401")
    var failure = AccountTestTranscript(startedAt: .now)
    for event in Flow.outputEvents(for: failed) { failure.apply(event, at: .now) }
    #expect(failure.displayLines == ["✕ API returned 401"])
    #expect(Flow.outputEvents(for: AccountTestRun(runID: "tr_3", accountID: 7, status: .running)).isEmpty)
}
