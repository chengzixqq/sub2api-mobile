import Foundation
import Sub2Core

// S2-14 fixtures: the account test's stream and test-runs on the demo site (20 §4). A test passes unless `testFail`; a pass
// clears an error and a rate limit and leaves the switch as it was, as the backend's recovery after a successful test does.
extension DemoData.AccountFixture {
    /// The upstream refuses the key: 401, and the account goes into error.
    static let testFail = "-ui-account-test-fail"
    /// The stream breaks after its first output; `latest` is an interrupted manual record, and 重新测试's run passes on its
    /// second read.
    static let testInterrupt = "-ui-account-test-interrupt"
    /// 1.5 seconds between events instead of 0.25, so a test can be closed while it runs.
    static let testSlow = "-ui-account-test-slow"
}

/// The async runs of this process (each UI test launches its own).
@MainActor private enum AccountTestRunLedger {
    static var started = 0
    static var accounts: [String: Int] = [:]
    static var reads: [String: Int] = [:]
    static var finished: [String: AccountTestRun] = [:]
}

extension AccountDemoStore {
    /// `POST :id/test`, replayed event by event; the account changes as test_result is sent. A blank model gets a test_start
    /// without one, so the header keeps “默认模型” where the server would name its default.
    func testStream(id: Int, model: String?, now: Date) throws -> AsyncThrowingStream<AccountTestEvent, any Error> {
        guard let before = account(id: id) else { throw APIError.server(status: 404, reason: AccountWriteReason.notFound) }
        let arguments = ProcessInfo.processInfo.arguments
        let interval: Duration = arguments.contains(DemoData.AccountFixture.testSlow) ? .milliseconds(1_500) : .milliseconds(250)
        let breaksOff = arguments.contains(DemoData.AccountFixture.testInterrupt)
        let passes = !arguments.contains(DemoData.AccountFixture.testFail)
        let after = Self.tested(before, passes: passes, now: now)
        let script = Self.testEvents(before: before, after: after, model: model, passes: passes, now: now)
        let events = breaksOff ? Array(script.prefix(2)) : script
        let pair = AsyncThrowingStream<AccountTestEvent, any Error>.makeStream()
        let task = Task { [weak self] in
            for event in events {
                do { try await Task.sleep(for: interval) } catch { return }
                if event.isTestResult { self?.replace(after) }
                pair.continuation.yield(event)
            }
            if breaksOff { pair.continuation.finish(throwing: APIError.incompleteStream) } else { pair.continuation.finish() }
        }
        pair.continuation.onTermination = { _ in task.cancel() }
        return pair.stream
    }
    /// `GET :id/test-runs/latest`: the interrupted manual record under `testInterrupt`, otherwise none (404).
    func latestTestRun(id: Int, now: Date) -> AccountTestRun? {
        guard ProcessInfo.processInfo.arguments.contains(DemoData.AccountFixture.testInterrupt) else { return nil }
        return AccountTestRun(runID: "tr_manual\(id)", accountID: id, source: "manual", status: .interrupted, startedAt: now, finishedAt: now)
    }
    /// `POST :id/test-runs`: 202 with a running run.
    func startTestRun(id: Int, model: String?, now: Date) throws -> AccountTestRunStart {
        guard account(id: id) != nil else { throw APIError.server(status: 404, reason: AccountWriteReason.notFound) }
        AccountTestRunLedger.started += 1
        let runID = "tr_fixture\(id)_\(AccountTestRunLedger.started)"
        AccountTestRunLedger.accounts[runID] = id
        return .started(AccountTestRun(runID: runID, accountID: id, source: "async", status: .running, model: model, startedAt: now))
    }
    /// `GET account-test-runs/:run_id`: running on the first read, finished from the second on (the account changes then).
    func testRun(runID: String, now: Date) throws -> AccountTestRun {
        if let finished = AccountTestRunLedger.finished[runID] { return finished }
        guard let id = AccountTestRunLedger.accounts[runID], let before = account(id: id) else {
            throw APIError.server(status: 404, reason: "ACCOUNT_TEST_RUN_NOT_FOUND")
        }
        let reads = (AccountTestRunLedger.reads[runID] ?? 0) + 1
        AccountTestRunLedger.reads[runID] = reads
        guard reads >= 2 else { return AccountTestRun(runID: runID, accountID: id, source: "async", status: .running, startedAt: now) }
        let passes = !ProcessInfo.processInfo.arguments.contains(DemoData.AccountFixture.testFail)
        replace(Self.tested(before, passes: passes, now: now))
        let run = passes
            ? AccountTestRun(runID: runID, accountID: id, source: "async", status: .success, latencyMs: 3_420, firstTokenMs: 1_210,
                             upstreamStatusCode: 200, recovery: Self.recovery(before, now: now), startedAt: now.addingTimeInterval(-6),
                             finishedAt: now, responseText: "你好，连接正常。")
            : AccountTestRun(runID: runID, accountID: id, source: "async", status: .failed, latencyMs: 820, upstreamStatusCode: 401,
                             errorKind: "auth", errorSummary: Self.authFailure, startedAt: now.addingTimeInterval(-6), finishedAt: now,
                             errorMessage: Self.upstreamError)
        AccountTestRunLedger.finished[runID] = run
        return run
    }

    private static let authFailure = "401 凭据已失效（invalid_api_key）"
    private static let upstreamError = "API returned 401: invalid x-api-key"

    private static func testEvents(before: UpstreamAccount, after: UpstreamAccount, model: String?, passes: Bool, now: Date) -> [AccountTestEvent] {
        let start = AccountTestEvent(type: "test_start", model: model.flatMap { $0.isEmpty ? nil : $0 })
        let result = AccountTestResult(success: passes, startedAt: now, firstTokenMs: passes ? 1_210 : nil, totalMs: passes ? 3_420 : 820,
                                       upstreamStatus: passes ? 200 : 401, usage: passes ? .init(inputTokens: 12, outputTokens: 128) : nil,
                                       account: .init(account: after), recovery: passes ? recovery(before, now: now) : nil,
                                       marked: .init(error: !passes && before.status != "error", rateLimited: false, tempUnschedulable: false))
        let verdict = passes ? [AccountTestEvent(type: "content", content: "你好，"), AccountTestEvent(type: "content", content: "连接正常。\n"),
                                AccountTestEvent(type: "test_complete", success: true)]
            : [AccountTestEvent(type: "error", message: upstreamError)]
        return [start] + verdict + [AccountTestEvent(type: "test_result", data: result)]
    }
    /// The account after the test: a pass clears the error and the limits, a failure marks a credential error and stops it.
    private static func tested(_ account: UpstreamAccount, passes: Bool, now: Date) -> UpstreamAccount {
        var updated = account
        if passes {
            if updated.status == "error" { updated.status = "active" }
            updated.errorMessage = nil; updated.errorSummary = nil; updated.errorKind = nil; updated.errorStatusCode = nil; updated.errorAt = nil
            updated.rateLimitResetAt = nil; updated.tempUnschedulableUntil = nil; updated.tempUnschedulableReason = nil
        } else {
            updated.status = "error"; updated.schedulable = false
            updated.errorMessage = authFailure; updated.errorSummary = authFailure; updated.errorKind = "auth"; updated.errorStatusCode = 401
            updated.errorAt = ServerTime.utcTimestamp(now)
        }
        return updated
    }
    private static func recovery(_ before: UpstreamAccount, now: Date) -> AccountTestResult.Recovery? {
        let limited = [before.rateLimitResetAt, before.tempUnschedulableUntil].contains { ServerTime.parseTimestamp($0).map { $0 > now } ?? false }
        guard before.status == "error" || limited else { return nil }
        return AccountTestResult.Recovery(clearedError: before.status == "error", clearedRateLimit: limited)
    }
}
