import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// 20 §4.4–§4.6: the session's account tests (S2-14): receipts after the sheet closes, the interruption check, the test-runs
// polling, the session guard and the background task.

private let testNow = Date(timeIntervalSince1970: 1_800_000_000)
private let transportError = APIError(kind: .transport, message: "无法连接站点")

private actor ManualSleeper {
    private(set) var requests: [Duration] = []
    private var waits: [CheckedContinuation<Void, Never>] = []
    func sleep(_ duration: Duration) async {
        requests.append(duration)
        await withCheckedContinuation { waits.append($0) }
    }
    var pending: Int { waits.count }
    func wakeAll() { let woken = waits; waits = []; woken.forEach { $0.resume() } }
}

@MainActor private final class FakeTestSource: AccountTestSource {
    var session: AccountTestSession?
    var isSuspended = false
    private(set) var calls: [String] = []
    private(set) var generations: [UUID] = []
    private(set) var streams: [AsyncThrowingStream<AccountTestEvent, any Error>.Continuation] = []
    var streamFailure: (any Error)?
    var latestReplies: [AccountTestRun?] = []
    var startReplies: [Result<AccountTestRunStart, any Error>] = []
    var runReplies: [Result<AccountTestRun, any Error>] = []
    var readBack = UpstreamAccount(id: 7, name: "主号", platform: "anthropic", type: "apikey", schedulable: false)

    init(testResult: Bool = true, testRuns: Bool = true, readOnly: Bool = false) {
        session = AccountTestSession(generation: UUID(), supportsTestResult: testResult, supportsTestRuns: testRuns, isReadOnlyToken: readOnly)
    }
    var generation: UUID { session?.generation ?? UUID() }
    func switchSession() {
        session = session.map { AccountTestSession(generation: UUID(), supportsTestResult: $0.supportsTestResult,
                                                   supportsTestRuns: $0.supportsTestRuns, isReadOnlyToken: $0.isReadOnlyToken) }
    }
    func count(_ prefix: String) -> Int { calls.filter { $0.hasPrefix(prefix) }.count }

    var accountTestSession: AccountTestSession? { session }
    func serverNow() -> Date { testNow }
    func accountWithVersion(id: Int) async throws -> VersionedAccount {
        calls.append("read \(id)")
        return VersionedAccount(account: readBack, etag: "\"cv-2\"")
    }
    func testAccountStream(id: Int, model: String?, generation: UUID) async throws -> AsyncThrowingStream<AccountTestEvent, any Error> {
        calls.append("stream \(id) \(model ?? "-")"); generations.append(generation)
        if let streamFailure { throw streamFailure }
        let pair = AsyncThrowingStream<AccountTestEvent, any Error>.makeStream()
        streams.append(pair.continuation)
        return pair.stream
    }
    func startAccountTestRun(id: Int, model: String?, generation: UUID) async throws -> AccountTestRunStart {
        calls.append("start \(id) \(model ?? "-")"); generations.append(generation)
        return try startReplies.isEmpty ? .started(run(.running)) : startReplies.removeFirst().get()
    }
    func latestAccountTestRun(id: Int) async throws -> AccountTestRun? {
        calls.append("latest \(id)")
        return latestReplies.isEmpty ? nil : latestReplies.removeFirst()
    }
    func accountTestRun(runID: String) async throws -> AccountTestRun {
        calls.append("run \(runID)")
        return try runReplies.isEmpty ? run(.running, id: runID) : runReplies.removeFirst().get()
    }
}

@MainActor private final class FakeScheduling: AccountTestScheduling {
    private(set) var enabled: [Int] = []
    var onChange: (@MainActor (UpstreamAccount) -> Void)?
    func enableScheduling(_ account: UpstreamAccount) async {
        enabled.append(account.id)
        var written = account
        written.schedulable = true
        onChange?(written)
    }
}

@MainActor private final class Opened { var ids: [Int] = [] }

@MainActor private final class FakeBackground {
    private(set) var begun = 0
    private(set) var ended: [Int] = []
    var token: Int? = 41
    var expire: (@MainActor @Sendable () -> Void)?
    var activity: AccountTestBackgroundActivity {
        AccountTestBackgroundActivity(begin: { [self] onExpire in begun += 1; expire = onExpire; return token }, end: { [self] in ended.append($0) })
    }
}

/// Everything one case drives.
@MainActor private struct Harness {
    let source: FakeTestSource
    let sleeper: ManualSleeper
    let receipts: ReceiptCenter
    let scheduling: FakeScheduling
    let background: FakeBackground
    let center: AccountTestCenter

    init(_ source: FakeTestSource = FakeTestSource()) {
        let sleeper = ManualSleeper(), scheduling = FakeScheduling(), background = FakeBackground()
        let receipts = ReceiptCenter(sleep: { _ in try await Task.sleep(for: .seconds(3_600)) })
        self.source = source; self.sleeper = sleeper; self.receipts = receipts; self.scheduling = scheduling; self.background = background
        center = AccountTestCenter(generation: source.generation, source: source, receipts: receipts,
                                   makeScheduling: { onChange in scheduling.onChange = onChange; return scheduling },
                                   background: background.activity, sleep: { await sleeper.sleep($0) })
    }
    func finishStream(_ events: [AccountTestEvent], throwing error: (any Error)? = nil, index: Int = 0) {
        for event in events { source.streams[index].yield(event) }
        if let error { source.streams[index].finish(throwing: error) } else { source.streams[index].finish() }
    }
    func waitForSleeps(_ count: Int) async {
        var spins = 0
        while await sleeper.pending < count, spins < 20_000 { await Task.yield(); spins += 1 }
    }
}

private func target(_ id: Int = 7, name: String = "主号", type: String = "apikey") -> AccountTestTarget {
    AccountTestTarget(account: UpstreamAccount(id: id, name: name, platform: "anthropic", type: type, status: "error", schedulable: false),
                      platformName: "Anthropic")
}
private func run(_ status: AccountTestRun.Status, id: String = "tr_fixture7", offset: TimeInterval = 1) -> AccountTestRun {
    AccountTestRun(runID: id, accountID: 7, status: status, latencyMs: 3420, firstTokenMs: 1210, startedAt: testNow.addingTimeInterval(offset))
}
private func result(_ success: Bool) -> AccountTestEvent {
    AccountTestEvent(type: "test_result", data: AccountTestResult(success: success, totalMs: 3420, upstreamStatus: success ? 200 : 401,
                                                                  account: .init(status: success ? "active" : "error", schedulable: false)))
}
private let partial = [AccountTestEvent(type: "test_start", model: "claude-sonnet-4-5"), AccountTestEvent(type: "content", content: "你好")]

@MainActor private func settle(until done: @MainActor () -> Bool) async {
    var spins = 0
    while !done(), spins < 20_000 { await Task.yield(); spins += 1 }
}
@MainActor private func ending(_ center: AccountTestCenter, _ id: Int = 7) -> AccountTestEnding? { center.state(for: id)?.ending }
/// A stream whose reader went away takes no more events.
private func isTerminated(_ stream: AsyncThrowingStream<AccountTestEvent, any Error>.Continuation) -> Bool {
    if case .terminated = stream.yield(AccountTestEvent(type: "status", content: "ping")) { true } else { false }
}

// MARK: - Stream tests

@MainActor @Test(.timeLimit(.minutes(1))) func streamResultFinishesAttachedTestWithoutReceipt() async {
    let h = Harness()
    #expect(h.center.start(target(), model: "claude-sonnet-4-5", opener: nil))
    #expect(h.center.isRunning(7))
    await settle { h.source.streams.count == 1 }
    #expect(h.center.state(for: 7)?.lines == ["→ 测试 Anthropic · 主号", "→ 模型 claude-sonnet-4-5"])
    h.finishStream(partial + [AccountTestEvent(type: "test_complete", success: true), result(true)])
    await settle { ending(h.center) != nil }
    guard case .finished(let outcome)? = ending(h.center) else { Issue.record("not finished"); return }
    #expect(outcome.passed)
    #expect(h.center.state(for: 7)?.lines.last == "你好")
    #expect(h.receipts.current == nil)
    guard case .tested(let state)? = h.center.completion(for: 7)?.change else { Issue.record("no completion"); return }
    #expect(state?.status == "active")
    #expect(h.source.calls == ["stream 7 claude-sonnet-4-5"])
    #expect(h.source.generations == [h.source.generation])
}

@MainActor @Test(.timeLimit(.minutes(1))) func closingWhileRunningShowsReceiptAndViewOpensAccount() async {
    let h = Harness()
    let opened = Opened()
    h.center.start(target(), model: nil, opener: { opened.ids.append($0) })
    await settle { h.source.streams.count == 1 }
    h.center.detach(7)
    #expect(h.center.state(for: 7)?.isDetached == true)
    h.finishStream([result(true)])
    await settle { h.receipts.current != nil }
    #expect(h.receipts.current?.text == "「主号」测试通过")
    #expect(h.receipts.current?.action?.title == "查看")
    #expect(h.center.state(for: 7) == nil)
    if let id = h.receipts.current?.id { h.receipts.performAction(id: id) }
    #expect(opened.ids == [7])

    h.center.start(target(), model: nil, opener: nil)
    await settle { h.source.streams.count == 2 }
    h.center.detach(7)
    h.finishStream([result(false)], index: 1)
    await settle { h.receipts.current?.text == "「主号」测试未通过" }
    #expect(h.receipts.current?.tone == .critical)
}

@MainActor @Test(.timeLimit(.minutes(1))) func attachAndDetachFollowTheSheet() async {
    let h = Harness()
    h.center.start(target(), model: nil, opener: nil)
    await settle { h.source.streams.count == 1 }
    h.center.detach(7); h.center.attach(7)
    h.finishStream([result(true)])
    await settle { ending(h.center) != nil }
    #expect(h.receipts.current == nil)
    h.center.detach(7)
    #expect(h.center.state(for: 7) == nil)
}

// MARK: - The interruption check (20 §4.4)

@MainActor @Test(.timeLimit(.minutes(1))) func streamEndingBeforeResultSettlesFromLatestRun() async {
    let h = Harness()
    h.source.latestReplies = [run(.success)]
    h.center.start(target(), model: nil, opener: nil)
    await settle { h.source.streams.count == 1 }
    h.finishStream(partial, throwing: transportError)
    await settle { ending(h.center) != nil }
    guard case .finished(let outcome)? = ending(h.center) else { Issue.record("not settled"); return }
    #expect(outcome.passed && outcome.account?.schedulable == false)
    #expect(h.source.calls == ["stream 7 -", "latest 7", "read 7"])
}

@MainActor @Test(.timeLimit(.minutes(1))) func interruptedLatestRunEndsInterruptedAndOffersRetest() async {
    let h = Harness()
    h.source.latestReplies = [run(.interrupted)]
    h.center.start(target(), model: nil, opener: nil)
    await settle { h.source.streams.count == 1 }
    h.center.detach(7)
    h.finishStream(partial, throwing: transportError)
    await settle { h.receipts.current != nil }
    #expect(h.receipts.current?.text == "测试被中断，不能判定是否成功")
    #expect(h.receipts.current?.action?.title == "重新测试")
    #expect(h.source.count("latest") == 1)
    if let id = h.receipts.current?.id { h.receipts.performAction(id: id) }
    await settle { h.source.count("start") == 1 }
    #expect(h.center.state(for: 7)?.isDetached == true)
    h.center.cancelAll()
    await h.sleeper.wakeAll()
}

@MainActor @Test(.timeLimit(.minutes(1))) func olderLatestRunIsReadOnceMoreThreeSecondsLater() async {
    let h = Harness()
    h.source.latestReplies = [run(.success, offset: -60), nil]
    h.center.start(target(), model: nil, opener: nil)
    await settle { h.source.streams.count == 1 }
    h.finishStream(partial, throwing: transportError)
    await h.waitForSleeps(1)
    #expect(await h.sleeper.requests == [.seconds(3)])
    #expect(h.source.count("latest") == 1)
    await h.sleeper.wakeAll()
    await settle { ending(h.center) != nil }
    #expect(ending(h.center) == .interrupted)
    #expect(h.source.count("latest") == 2 && h.source.count("read") == 0)
}

@MainActor @Test(.timeLimit(.minutes(1))) func withoutTestRunsADisconnectIsInterrupted() async {
    let h = Harness(FakeTestSource(testRuns: false))
    h.center.start(target(), model: nil, opener: nil)
    await settle { h.source.streams.count == 1 }
    h.finishStream(partial, throwing: CancellationError())
    await settle { ending(h.center) != nil }
    #expect(ending(h.center) == .interrupted)
    #expect(h.source.count("latest") == 0)
}

@MainActor @Test(.timeLimit(.minutes(1))) func disconnectWhileSuspendedChecksOnlyInTheForeground() async {
    let h = Harness()
    h.source.isSuspended = true
    h.center.start(target(), model: nil, opener: nil)
    await settle { h.source.streams.count == 1 }
    h.finishStream(partial, throwing: transportError)
    await h.waitForSleeps(1)
    await h.sleeper.wakeAll()
    await h.waitForSleeps(1)
    #expect(h.source.count("latest") == 0)
    h.source.isSuspended = false
    h.source.latestReplies = [run(.failed)]
    await h.sleeper.wakeAll()
    await settle { ending(h.center) != nil }
    #expect(h.source.count("latest") == 1)
    guard case .finished(let outcome)? = ending(h.center) else { Issue.record("not settled"); return }
    #expect(!outcome.passed)
}

@MainActor @Test(.timeLimit(.minutes(1))) func legacyServerComparesTheSnapshotsAfterEOF() async {
    let h = Harness(FakeTestSource(testResult: false, testRuns: false))
    h.source.readBack = UpstreamAccount(id: 7, name: "主号", platform: "anthropic", type: "apikey", status: "active", schedulable: false)
    h.center.start(target(), model: nil, opener: nil)
    await settle { h.source.streams.count == 1 }
    h.finishStream([AccountTestEvent(type: "content", content: "ok"), AccountTestEvent(type: "test_complete", success: true)])
    await settle { ending(h.center) != nil }
    guard case .finished(let outcome)? = ending(h.center) else { Issue.record("not finished"); return }
    #expect(outcome.passed && outcome.timing?.isLocal == true)
    #expect(outcome.recovery?.clearedError == true && outcome.account?.status == "active")
    #expect(h.source.count("read") == 1)
}

// MARK: - 重新测试 through test-runs (20 §4.4, §4.6)

@MainActor @Test(.timeLimit(.minutes(1))) func retestStartsARunAndPollsEveryThreeSeconds() async {
    let h = Harness()
    h.source.runReplies = [.success(run(.running)), .success(run(.success))]
    #expect(h.center.retest(target(), model: "claude-x", opener: nil))
    #expect(h.center.state(for: 7)?.phase == .running(polling: true))
    await h.waitForSleeps(1)
    await h.sleeper.wakeAll()
    await settle { h.source.count("run") == 1 }
    await h.waitForSleeps(1)
    await h.sleeper.wakeAll()
    await settle { ending(h.center) != nil }
    #expect(await h.sleeper.requests == [.seconds(3), .seconds(3)])
    #expect(h.source.calls == ["start 7 claude-x", "run tr_fixture7", "run tr_fixture7", "read 7"])
    guard case .finished(let outcome)? = ending(h.center) else { Issue.record("not finished"); return }
    #expect(outcome.passed && outcome.timing?.totalMs == 3420)
    #expect(h.background.begun == 0)
}

@MainActor @Test(.timeLimit(.minutes(1))) func pollingSkipsRequestsWhileSuspended() async {
    let h = Harness()
    h.source.isSuspended = true
    h.center.retest(target(), model: nil, opener: nil)
    for _ in 0..<3 {
        await h.waitForSleeps(1)
        await h.sleeper.wakeAll()
    }
    await h.waitForSleeps(1)
    #expect(h.source.count("run") == 0)
    h.source.isSuspended = false
    h.source.runReplies = [.success(run(.failed))]
    await h.sleeper.wakeAll()
    await settle { ending(h.center) != nil }
    #expect(h.source.count("run") == 1)
}

@MainActor @Test(.timeLimit(.minutes(1))) func alreadyRunningPollsTheReturnedRun() async {
    let h = Harness()
    h.source.startReplies = [.success(.alreadyRunning(runID: "tr_other"))]
    h.source.runReplies = [.success(run(.success, id: "tr_other"))]
    h.center.retest(target(), model: nil, opener: nil)
    await h.waitForSleeps(1)
    await h.sleeper.wakeAll()
    await settle { ending(h.center) != nil }
    #expect(h.source.calls.prefix(2) == ["start 7 -", "run tr_other"])
}

@MainActor @Test(.timeLimit(.minutes(1))) func busyStartIsNotRetried() async {
    let h = Harness()
    h.source.startReplies = [.failure(APIError(kind: .rateLimited, reason: "ACCOUNT_TEST_BUSY", statusCode: 429, message: "满", retryAfter: 30))]
    h.center.retest(target(), model: nil, opener: nil)
    h.center.detach(7)
    await settle { h.receipts.current != nil }
    #expect(h.receipts.current?.text == "测试没有开始：站点同时运行的测试已满，请稍后再试")
    #expect(h.receipts.current?.action == nil)
    #expect(h.source.count("start") == 1 && h.source.count("stream") == 0)
    #expect(await h.sleeper.requests.isEmpty)
}

@MainActor @Test(.timeLimit(.minutes(1))) func vendorForbiddenFallsBackToTheStream() async {
    let h = Harness()
    h.source.startReplies = [.failure(APIError(kind: .permission, reason: "FORBIDDEN", statusCode: 403, message: "x"))]
    h.center.retest(target(), model: "m", opener: nil)
    await settle { h.source.streams.count == 1 }
    #expect(h.center.state(for: 7)?.phase == .running(polling: false))
    h.finishStream([result(true)])
    await settle { ending(h.center) != nil }
    #expect(h.source.calls == ["start 7 m", "stream 7 m"])

    let legacy = Harness(FakeTestSource(testRuns: false))
    legacy.center.retest(target(), model: nil, opener: nil)
    await settle { legacy.source.streams.count == 1 }
    #expect(legacy.source.count("start") == 0)
}

@MainActor @Test(.timeLimit(.minutes(1))) func pollingGivesUpAfterTenFailuresOrAMissingRun() async {
    let h = Harness()
    h.source.runReplies = Array(repeating: .failure(transportError), count: 10)
    h.center.retest(target(), model: nil, opener: nil)
    for _ in 0..<10 {
        await h.waitForSleeps(1)
        await h.sleeper.wakeAll()
    }
    await settle { ending(h.center) != nil }
    #expect(ending(h.center) == .interrupted && h.source.count("run") == 10)

    let missing = Harness()
    missing.source.runReplies = [.failure(APIError.server(status: 404, reason: "ACCOUNT_TEST_RUN_NOT_FOUND"))]
    missing.center.retest(target(), model: nil, opener: nil)
    await missing.waitForSleeps(1)
    await missing.sleeper.wakeAll()
    await settle { ending(missing.center) != nil }
    #expect(ending(missing.center) == .interrupted && missing.source.count("run") == 1)
}

// MARK: - Guards

@MainActor @Test(.timeLimit(.minutes(1))) func sameAccountRunsOneTestAtATime() async {
    let h = Harness()
    #expect(h.center.start(target(), model: nil, opener: nil))
    #expect(!h.center.start(target(), model: nil, opener: nil))
    #expect(!h.center.retest(target(), model: nil, opener: nil))
    #expect(h.center.start(target(3, name: "副号"), model: nil, opener: nil))
    await settle { h.source.streams.count == 2 }
    #expect(h.center.isRunning(7) && h.center.isRunning(3))
    h.finishStream([result(true)])
    await settle { ending(h.center) != nil }
    #expect(h.center.start(target(), model: "again", opener: nil))
    #expect(h.center.isRunning(7))
    h.center.cancelAll()
}

@MainActor @Test func readOnlyTokenNeverStarts() {
    let h = Harness(FakeTestSource(readOnly: true))
    #expect(!h.center.start(target(), model: nil, opener: nil))
    #expect(ending(h.center) == .notStarted(.readOnly))
    #expect(h.source.calls.isEmpty && h.background.begun == 0)
}

@MainActor @Test(.timeLimit(.minutes(1))) func openFailureMarksNotStarted() async {
    let h = Harness()
    h.source.streamFailure = APIError.server(status: 500, reason: nil)
    h.center.start(target(), model: nil, opener: nil)
    await settle { ending(h.center) != nil }
    guard case .notStarted(.failed)? = ending(h.center) else { Issue.record("not a failure"); return }
    #expect(h.center.state(for: 7)?.content?.title.hasPrefix("测试没有开始：") == true)
    #expect(h.center.state(for: 7)?.content?.offersRetest == true)
    #expect(h.background.ended == [41])
    #expect(h.center.retry(7))
    await settle { h.source.count("stream") == 2 }
    #expect(h.source.count("start") == 0)

    let cancelled = Harness()
    cancelled.source.streamFailure = APIError(kind: .stepUp, reason: "STEP_UP_REQUIRED", statusCode: 403, message: "x", securityOutcome: .cancelled)
    cancelled.center.start(target(), model: nil, opener: nil)
    cancelled.center.detach(7)
    await settle { cancelled.center.state(for: 7) == nil }
    #expect(cancelled.receipts.current == nil)
}

@MainActor @Test(.timeLimit(.minutes(1))) func sessionChangeDiscardsResults() async {
    let h = Harness()
    h.center.start(target(), model: nil, opener: nil)
    h.center.detach(7)
    await settle { h.source.streams.count == 1 }
    h.source.switchSession()
    h.finishStream(partial, throwing: transportError)
    for _ in 0..<200 { await Task.yield() }
    #expect(h.center.isRunning(7))
    #expect(h.center.completions.isEmpty && h.receipts.current == nil && h.source.count("latest") == 0)
}

@MainActor @Test(.timeLimit(.minutes(1))) func backgroundTaskIsHeldWhileTheStreamRuns() async {
    let h = Harness()
    h.center.start(target(), model: nil, opener: nil)
    await settle { h.source.streams.count == 1 }
    #expect(h.background.begun == 1 && h.background.ended.isEmpty)
    h.background.expire?()
    #expect(h.background.ended == [41])
    #expect(h.center.isRunning(7))
    h.finishStream([result(true)])
    await settle { ending(h.center) != nil }
    #expect(h.background.ended == [41])
}

@MainActor @Test(.timeLimit(.minutes(1))) func cancelAllStopsTestsAndReturnsTheBackgroundTasks() async {
    let h = Harness()
    h.center.start(target(), model: nil, opener: nil)
    h.center.start(target(3, name: "副号"), model: nil, opener: nil)
    await settle { h.source.streams.count == 2 }
    h.center.detach(7)
    h.center.cancelAll()
    await settle { h.source.streams.allSatisfy(isTerminated) }
    #expect(h.source.streams.allSatisfy(isTerminated))
    #expect(h.background.ended == [41, 41])
    #expect(h.center.states.isEmpty && h.center.completions.isEmpty && h.receipts.current == nil)
}

@MainActor @Test(.timeLimit(.minutes(1))) func enableSchedulingReusesOneActionsAndPostsTheWrite() async {
    let h = Harness()
    await h.center.enableScheduling(target().account)
    guard case .written(let account)? = h.center.completion(for: 7)?.change else { Issue.record("no write"); return }
    #expect(account.schedulable)
    let first = h.center.completion(for: 7)?.id
    await h.center.enableScheduling(target().account)
    #expect(h.scheduling.enabled == [7, 7])
    #expect(h.center.completion(for: 7)?.id != first)
}

@MainActor @Test func showAccountPushesOnlyWhenNotAlreadyOnTop() {
    let router = AppRouter(selectedTab: .accounts)
    router.showAccount(id: 7)
    #expect(router.path(for: .accounts) == [.account(id: 7)])
    router.setPath([.account(id: 7, focus: .models)], for: .accounts)
    router.showAccount(id: 7)
    #expect(router.path(for: .accounts).count == 1)
    router.setPath([.account(id: 3)], for: .accounts)
    router.showAccount(id: 7)
    #expect(router.path(for: .accounts) == [.account(id: 3), .account(id: 7)])
}

// MARK: - 新建账号（S2-20）: the test, then the switch on, held by the center so closing the form does not stop it

@MainActor private final class FakeScheduleWriter: AccountNewScheduleWriter {
    var session: AccountWriteSession?
    var readBacks: [Result<UpstreamAccount, any Error>] = []
    var switches: [Result<UpstreamAccount, any Error>] = []
    var switchesSessionOnRead = false
    private(set) var reads = 0
    private(set) var sent: [(enabled: Bool, key: UUID?, generation: UUID)] = []

    init(generation: UUID, idempotentWrites: Bool = true) {
        session = AccountWriteSession(generation: generation, idempotentWrites: idempotentWrites, recoverSchedulable: true, patch: true,
                                      isReadOnlyToken: false)
    }
    var accountWriteSession: AccountWriteSession? { session }
    func setAccountSchedulable(id: Int, enabled: Bool, idempotencyKey: UUID?, generation: UUID) async throws -> WriteOutcome<UpstreamAccount> {
        sent.append((enabled, idempotencyKey, generation))
        return WriteOutcome(value: try (switches.isEmpty ? .success(newAccount(schedulable: true)) : switches.removeFirst()).get())
    }
    func accountWithVersion(id: Int) async throws -> VersionedAccount {
        reads += 1
        if switchesSessionOnRead, let current = session {
            session = AccountWriteSession(generation: UUID(), idempotentWrites: current.idempotentWrites, recoverSchedulable: true, patch: true,
                                          isReadOnlyToken: false)
        }
        return VersionedAccount(account: try (readBacks.isEmpty ? .success(newAccount()) : readBacks.removeFirst()).get(), etag: "\"cv-1\"")
    }
}

@MainActor private final class KeyMaker {
    private(set) var made: [UUID] = []
    func make() -> UUID { let key = UUID(); made.append(key); return key }
}

private func newAccount(status: String = "active", schedulable: Bool = false) -> UpstreamAccount {
    UpstreamAccount(id: 13, name: "Claude-04", platform: "anthropic", type: "apikey", status: status, schedulable: schedulable)
}
private func newTarget() -> AccountTestTarget { AccountTestTarget(account: newAccount(), platformName: "Anthropic") }
private func newResult(_ success: Bool, marked: Bool = false, status: String? = nil) -> AccountTestEvent {
    AccountTestEvent(type: "test_result", data: AccountTestResult(
        success: success, firstTokenMs: success ? 1210 : nil, totalMs: 3420, upstreamStatus: success ? 200 : 401,
        account: .init(status: status ?? (success ? "active" : "error"), schedulable: false, errorKind: success ? nil : "auth"),
        recovery: success ? .init(clearedError: false, clearedRateLimit: false) : nil,
        marked: success ? nil : .init(error: marked, rateLimited: false, tempUnschedulable: false)))
}

/// One new-account case: the harness, the writer (held here: the run keeps it weakly), the keys made and the accounts opened.
@MainActor private struct NewAccountCase {
    let h: Harness
    let writer: FakeScheduleWriter
    let keys = KeyMaker()
    let opened = Opened()

    init(source: FakeTestSource = FakeTestSource(), idempotentWrites: Bool = true) {
        h = Harness(source)
        writer = FakeScheduleWriter(generation: source.generation, idempotentWrites: idempotentWrites)
    }
    @discardableResult
    func start(status: AccountNewScheduleStatus = .paused, model: String? = "claude-sonnet-4-5") -> AccountNewTestRun? {
        let keys = keys, opened = opened
        return h.center.startNewAccountTest(newTarget(), model: model, status: status, writer: writer, opener: { opened.ids.append($0) },
                                            makeKey: { keys.make() })
    }
    /// The attached test ends with `events`; the run's follow-up (read, switch) has finished when this returns.
    func finish(_ events: [AccountTestEvent], index: Int = 0) async {
        await settle { h.source.streams.count > index }
        h.finishStream(events, index: index)
        await settle { h.center.state(for: 13)?.ending != nil }
        await h.center.newAccountRun(for: 13)?.settled()
    }
}

@MainActor @Test(.timeLimit(.minutes(1))) func newAccountPassEnablesSchedulingQuietlyWhileAttached() async throws {
    let c = NewAccountCase()
    let run = try #require(c.start())
    #expect(run.phase == .testing && c.h.center.newAccountRun(for: 13) === run)
    await c.finish(partial + [newResult(true)])
    #expect(run.phase == .passed && run.verdict?.passed == true && run.latest?.etag == "\"cv-1\"")
    #expect(c.writer.reads == 1 && c.writer.sent.count == 1)
    #expect(c.writer.sent.first?.enabled == true && c.writer.sent.first?.key == c.keys.made.first && c.keys.made.count == 1)
    #expect(c.writer.sent.first?.generation == c.h.source.generation)
    #expect(c.h.receipts.current == nil)
    #expect(c.h.center.completion(for: 13) != nil && c.h.center.state(for: 13)?.ending != nil)

    let unkeyed = NewAccountCase(idempotentWrites: false)
    let other = try #require(unkeyed.start())
    await unkeyed.finish([newResult(true)])
    #expect(other.phase == .passed && unkeyed.writer.sent.first?.key == nil && unkeyed.keys.made.isEmpty)
}

@MainActor @Test(.timeLimit(.minutes(1))) func newAccountFailureLeavesSchedulingOffWithTheHeldStatus() async throws {
    let c = NewAccountCase()
    let run = try #require(c.start())
    await c.finish([AccountTestEvent(type: "error", message: "invalid x-api-key Bearer abc"), newResult(false, marked: true)])
    #expect(run.phase == .failed && run.status == .error && c.writer.sent.isEmpty)
    #expect(run.verdict?.reason == "API Key 无效或已撤销" && run.verdict?.detailLine == "上游返回 401 · invalid x-api-key [已隐藏]")

    let quiet = NewAccountCase()
    let paused = try #require(quiet.start())
    await quiet.finish([newResult(false, marked: false, status: "active")])
    #expect(paused.phase == .failed && paused.status == .paused && quiet.writer.sent.isEmpty)
}

@MainActor @Test(.timeLimit(.minutes(1))) func unconfirmedEnableReadsBackThenRetriesWithTheSameKey() async throws {
    let c = NewAccountCase()
    let lost = KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil)
    c.writer.switches = [.failure(lost)]
    c.writer.readBacks = [.success(newAccount()), .success(newAccount())]
    let run = try #require(c.start())
    await c.finish([newResult(true)])
    guard case .enableFailed = run.phase else { Issue.record("\(run.phase)"); return }
    #expect(c.writer.reads == 2)
    run.retryEnable()
    await run.settled()
    #expect(run.phase == .passed && c.writer.sent.count == 2 && c.writer.sent[1].key == c.writer.sent[0].key && c.keys.made.count == 1)
}

@MainActor @Test(.timeLimit(.minutes(1))) func readBackShowingEnabledCountsAsPassed() async throws {
    let c = NewAccountCase()
    c.writer.switches = [.failure(transportError)]
    c.writer.readBacks = [.success(newAccount()), .success(newAccount(schedulable: true))]
    let run = try #require(c.start())
    await c.finish([newResult(true)])
    #expect(run.phase == .passed && c.writer.sent.count == 1)

    let on = NewAccountCase()
    on.writer.readBacks = [.success(newAccount(schedulable: true))]
    let already = try #require(on.start())
    await on.finish([newResult(true)])
    #expect(already.phase == .passed && on.writer.sent.isEmpty)
}

@MainActor @Test(.timeLimit(.minutes(1))) func definiteEnableFailureRetriesWithANewKey() async throws {
    let c = NewAccountCase()
    c.writer.switches = [.failure(APIError.server(status: 400, reason: nil))]
    let run = try #require(c.start())
    await c.finish([newResult(true)])
    guard case .enableFailed(let reason) = run.phase else { Issue.record("\(run.phase)"); return }
    #expect(reason?.isEmpty == false && c.writer.reads == 1)
    run.retryEnable()
    await run.settled()
    #expect(run.phase == .passed && c.writer.sent.count == 2 && c.writer.sent[1].key != c.writer.sent[0].key && c.keys.made.count == 2)

    let unkeyed = NewAccountCase(idempotentWrites: false)
    unkeyed.writer.switches = [.failure(APIError.server(status: 400, reason: nil))]
    let other = try #require(unkeyed.start())
    await unkeyed.finish([newResult(true)])
    other.retryEnable()
    await other.settled()
    #expect(unkeyed.writer.sent.map(\.key) == [nil, nil] && other.phase == .passed)
}

@MainActor @Test(.timeLimit(.minutes(1))) func detachedRunAnnouncesBackgroundThenThePassOpensTheAccount() async throws {
    let c = NewAccountCase()
    let run = try #require(c.start())
    await settle { c.h.source.streams.count == 1 }
    c.h.center.detachNewAccountTest(13)
    #expect(run.isDetached && c.h.center.state(for: 13)?.isDetached == true)
    #expect(c.h.receipts.current?.text == "「Claude-04」在后台继续测试，完成后通知你" && c.h.receipts.current?.action == nil)
    c.h.finishStream([newResult(true)])
    await settle { c.h.receipts.current?.text == "「Claude-04」测试通过 · 已启用调度" }
    #expect(c.h.receipts.current?.text == "「Claude-04」测试通过 · 已启用调度" && c.h.receipts.current?.action?.title == "查看")
    if let id = c.h.receipts.current?.id { c.h.receipts.performAction(id: id) }
    #expect(c.opened.ids == [13] && run.phase == .passed)
    #expect(c.h.center.newAccountRun(for: 13) == nil && c.h.center.state(for: 13) == nil)
}

@MainActor @Test(.timeLimit(.minutes(1))) func detachedFailureReceiptNamesTheHeldStatusAndResolveOpensTheAccount() async throws {
    let c = NewAccountCase()
    try #require(c.start())
    await settle { c.h.source.streams.count == 1 }
    c.h.center.detachNewAccountTest(13)
    c.h.finishStream([newResult(false, marked: true)])
    await settle { c.h.receipts.current?.text.contains("测试未通过") == true }
    #expect(c.h.receipts.current?.text == "「Claude-04」测试未通过 · 已标为错误（已停止调度）" && c.h.receipts.current?.action?.title == "处理")
    if let id = c.h.receipts.current?.id { c.h.receipts.performAction(id: id) }
    #expect(c.opened.ids == [13])

    let quiet = NewAccountCase()
    try #require(quiet.start())
    await settle { quiet.h.source.streams.count == 1 }
    quiet.h.center.detachNewAccountTest(13)
    quiet.h.finishStream([newResult(false, status: "active")])
    await settle { quiet.h.receipts.current?.text == "「Claude-04」测试未通过 · 仍暂停调度" }
    #expect(quiet.h.receipts.current?.text == "「Claude-04」测试未通过 · 仍暂停调度" && quiet.h.receipts.current?.tone == .critical)
}

@MainActor @Test(.timeLimit(.minutes(1))) func detachedEnableFailureReceipt() async throws {
    let c = NewAccountCase()
    c.writer.switches = [.failure(APIError.server(status: 400, reason: nil))]
    try #require(c.start())
    await settle { c.h.source.streams.count == 1 }
    c.h.center.detachNewAccountTest(13)
    c.h.finishStream([newResult(true)])
    await settle { c.h.receipts.current?.text == "「Claude-04」测试通过 · 启用调度没有成功" }
    #expect(c.h.receipts.current?.tone == .caution && c.h.receipts.current?.action?.title == "查看")
}

@MainActor @Test(.timeLimit(.minutes(1))) func incompleteNewAccountTestNeverEnables() async throws {
    let c = NewAccountCase(source: FakeTestSource(testRuns: false))
    let run = try #require(c.start())
    await settle { c.h.source.streams.count == 1 }
    c.h.center.detachNewAccountTest(13)
    c.h.finishStream(partial, throwing: transportError)
    await settle { c.h.receipts.current?.text.contains("中断") == true }
    #expect(run.phase == .interrupted && c.writer.sent.isEmpty && c.writer.reads == 0)
    #expect(c.h.receipts.current?.text == "「Claude-04」测试被中断，不能判定是否成功 · 仍暂停调度" && c.h.receipts.current?.action?.title == "处理")

    let refused = NewAccountCase()
    refused.h.source.streamFailure = APIError.server(status: 500, reason: nil)
    let notStarted = try #require(refused.start())
    await settle { notStarted.phase != .testing }
    guard case .notStarted(let message) = notStarted.phase else { Issue.record("\(notStarted.phase)"); return }
    #expect(message.hasPrefix("测试没有开始") && refused.writer.sent.isEmpty)
}

@MainActor @Test(.timeLimit(.minutes(1))) func sessionChangeOrAGoneWriterDropsTheRunWithoutWrites() async throws {
    let c = NewAccountCase()
    c.writer.switchesSessionOnRead = true
    let run = try #require(c.start())
    await settle { c.h.source.streams.count == 1 }
    c.h.center.detachNewAccountTest(13)
    c.h.finishStream([newResult(true)])
    await settle { c.writer.reads == 1 }
    await run.settled()
    #expect(c.writer.sent.isEmpty && run.phase == .testing)
    #expect(c.h.receipts.current?.text == "「Claude-04」在后台继续测试，完成后通知你")

    var gone: NewAccountCase? = NewAccountCase()
    let orphan = try #require(gone?.start())
    let center = try #require(gone?.h.center), source = try #require(gone?.h.source), receipts = try #require(gone?.h.receipts)
    await settle { source.streams.count == 1 }
    center.detachNewAccountTest(13)
    gone = nil
    source.streams[0].yield(newResult(true))
    source.streams[0].finish()
    await settle { orphan.verdict != nil }
    await orphan.settled()
    #expect(orphan.verdict != nil && orphan.phase == .testing)
    #expect(receipts.current?.text == "「Claude-04」在后台继续测试，完成后通知你")
}

@MainActor @Test(.timeLimit(.minutes(1))) func genericCompletionReceiptIsLeftOutForNewAccounts() async throws {
    let c = NewAccountCase()
    c.h.center.start(target(), model: nil, opener: nil)
    try #require(c.start())
    await settle { c.h.source.streams.count == 2 }
    c.h.center.detach(7)
    c.h.center.detachNewAccountTest(13)
    c.h.finishStream([result(true)], index: 0)
    await settle { c.h.receipts.current?.text == "「主号」测试通过" }
    c.h.finishStream([newResult(true)], index: 1)
    await settle { c.h.center.state(for: 13) == nil }
    #expect(c.h.receipts.current?.text != "「Claude-04」测试通过")
    await settle { c.h.receipts.current?.text == "「Claude-04」测试通过 · 已启用调度" }
    #expect(c.h.receipts.current?.text == "「Claude-04」测试通过 · 已启用调度" && c.h.center.completion(for: 13) != nil)
}

@MainActor @Test(.timeLimit(.minutes(1))) func restartEndAndCancelAll() async throws {
    let c = NewAccountCase()
    let run = try #require(c.start(status: .paused))
    await c.finish([newResult(false, marked: true)])
    #expect(run.status == .error)
    let again = try #require(c.start(status: .paused, model: "claude-haiku-4-5"))
    #expect(again === run && run.phase == .testing && run.status == .error && run.verdict == nil)
    #expect(c.start() == nil)
    await settle { c.h.source.streams.count == 2 }
    #expect(c.h.source.calls.last == "stream 13 claude-haiku-4-5")
    c.h.center.endNewAccountTest(13)
    #expect(c.h.center.newAccountRun(for: 13) == nil && c.h.center.isRunning(13))

    let other = NewAccountCase()
    try #require(other.start())
    other.h.center.cancelAll()
    #expect(other.h.center.newAccountRuns.isEmpty && other.h.center.states.isEmpty)
}

@MainActor @Test(.timeLimit(.minutes(1))) func passedRunIsNotTestedAgain() async throws {
    // Scheduling is on (or may be) once the test passed; another model's failure would leave it on and the sheet would read paused.
    let c = NewAccountCase()
    let run = try #require(c.start())
    await c.finish([newResult(true)])
    #expect(run.phase == .passed && c.writer.sent.count == 1)
    #expect(c.start(model: "claude-haiku-4-5") == nil)
    #expect(run.phase == .passed && run.verdict?.passed == true && c.h.source.streams.count == 1)

    let refused = NewAccountCase()
    refused.writer.switches = [.failure(APIError.server(status: 400, reason: nil))]
    let other = try #require(refused.start())
    await refused.finish([newResult(true)])
    guard case .enableFailed = other.phase else { Issue.record("\(other.phase)"); return }
    #expect(refused.start(model: "claude-haiku-4-5") == nil)
    guard case .enableFailed = other.phase else { Issue.record("\(other.phase)"); return }
    #expect(refused.h.source.streams.count == 1)
}
