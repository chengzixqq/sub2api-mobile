import Foundation
import Testing
import Sub2Core
@testable import NativeSessionSupport

// X17, 20 §1.6 (S2-23): AccountTestCenter's onFinished, through which home reads past the cache and the account list reads again
// after a test. The center's own behaviour is AccountTestCenterTests.

private let finishNow = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor private final class FinishSource: AccountTestSource {
    var session: AccountTestSession? = AccountTestSession(generation: UUID(), supportsTestResult: true, supportsTestRuns: true,
                                                          isReadOnlyToken: false)
    var isSuspended = false
    var latestReplies: [AccountTestRun?] = []
    private(set) var streams: [AsyncThrowingStream<AccountTestEvent, any Error>.Continuation] = []
    var generation: UUID { session?.generation ?? UUID() }
    var accountTestSession: AccountTestSession? { session }
    func switchSession() {
        session = AccountTestSession(generation: UUID(), supportsTestResult: true, supportsTestRuns: true, isReadOnlyToken: false)
    }
    func serverNow() -> Date { finishNow }
    func accountWithVersion(id: Int) async throws -> VersionedAccount {
        VersionedAccount(account: UpstreamAccount(id: id, name: "主号", platform: "anthropic", type: "apikey", schedulable: false), etag: "\"cv-2\"")
    }
    func testAccountStream(id: Int, model: String?, generation: UUID) async throws -> AsyncThrowingStream<AccountTestEvent, any Error> {
        let pair = AsyncThrowingStream<AccountTestEvent, any Error>.makeStream()
        streams.append(pair.continuation)
        return pair.stream
    }
    func startAccountTestRun(id: Int, model: String?, generation: UUID) async throws -> AccountTestRunStart { throw CancellationError() }
    func latestAccountTestRun(id: Int) async throws -> AccountTestRun? { latestReplies.isEmpty ? nil : latestReplies.removeFirst() }
    func accountTestRun(runID: String) async throws -> AccountTestRun { throw CancellationError() }
}

@MainActor private final class FinishScheduling: AccountTestScheduling {
    var onChange: (@MainActor (UpstreamAccount) -> Void)?
    func enableScheduling(_ account: UpstreamAccount) async {
        var written = account
        written.schedulable = true
        onChange?(written)
    }
}

@MainActor private final class FinishWriter: AccountNewScheduleWriter {
    let accountWriteSession: AccountWriteSession?
    private(set) var sent = 0
    init(generation: UUID) {
        accountWriteSession = AccountWriteSession(generation: generation, idempotentWrites: true, recoverSchedulable: true, patch: true,
                                                  isReadOnlyToken: false)
    }
    func setAccountSchedulable(id: Int, enabled: Bool, idempotencyKey: UUID?, generation: UUID) async throws -> WriteOutcome<UpstreamAccount> {
        sent += 1
        return WriteOutcome(value: UpstreamAccount(id: id, name: "Claude-04", platform: "anthropic", type: "apikey", schedulable: enabled))
    }
    func accountWithVersion(id: Int) async throws -> VersionedAccount {
        VersionedAccount(account: UpstreamAccount(id: id, name: "Claude-04", platform: "anthropic", type: "apikey", schedulable: false), etag: "\"cv-1\"")
    }
}

/// The ids onFinished got, and how many switches the writer had sent at each call.
@MainActor private final class Finished {
    var ids: [Int] = []
    var sentWhenCalled: [Int] = []
}

@MainActor private func makeCenter(_ source: FinishSource, _ finished: Finished, writer: FinishWriter? = nil) -> AccountTestCenter {
    let scheduling = FinishScheduling()
    return AccountTestCenter(generation: source.generation, source: source, receipts: ReceiptCenter(sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }),
                             makeScheduling: { onChange in scheduling.onChange = onChange; return scheduling },
                             sleep: { _ in try await Task.sleep(for: .seconds(3_600)) },
                             onFinished: { [weak writer] in finished.ids.append($0); finished.sentWhenCalled.append(writer?.sent ?? 0) })
}
@MainActor private func settle(until done: @MainActor () -> Bool) async {
    var spins = 0
    while !done(), spins < 20_000 { await Task.yield(); spins += 1 }
}
private func target(_ id: Int = 7, name: String = "主号") -> AccountTestTarget {
    AccountTestTarget(account: UpstreamAccount(id: id, name: name, platform: "anthropic", type: "apikey", status: "error", schedulable: false),
                      platformName: "Anthropic")
}
private func result(_ success: Bool) -> AccountTestEvent {
    AccountTestEvent(type: "test_result", data: AccountTestResult(success: success, totalMs: 3420, upstreamStatus: success ? 200 : 401,
                                                                  account: .init(status: success ? "active" : "error", schedulable: false)))
}

@MainActor @Test(.timeLimit(.minutes(1))) func finishedTestsCallOnFinishedOnceUnlessSessionChanged() async {
    let source = FinishSource(), finished = Finished()
    let center = makeCenter(source, finished)
    center.start(target(), model: nil, opener: nil)
    await settle { source.streams.count == 1 }
    #expect(finished.ids.isEmpty)
    source.streams[0].yield(result(true)); source.streams[0].finish()
    await settle { center.completion(for: 7) != nil }
    #expect(finished.ids == [7])
    center.start(target(), model: nil, opener: nil)
    await settle { source.streams.count == 2 }
    source.streams[1].yield(result(false)); source.streams[1].finish()
    await settle { finished.ids.count == 2 }
    // Cut before test_result, settled from test-runs/latest.
    source.latestReplies = [AccountTestRun(runID: "tr_fixture7", accountID: 7, status: .failed, latencyMs: 3420, firstTokenMs: 1210,
                                                startedAt: finishNow.addingTimeInterval(1))]
    center.start(target(), model: nil, opener: nil)
    await settle { source.streams.count == 3 }
    source.streams[2].finish(throwing: APIError(kind: .transport, message: "无法连接站点"))
    await settle { finished.ids.count == 3 }
    await center.enableScheduling(target().account)
    #expect(finished.ids == [7, 7, 7, 7])
    center.start(target(3, name: "副号"), model: nil, opener: nil)
    await settle { source.streams.count == 4 }
    source.switchSession()
    source.streams[3].yield(result(true)); source.streams[3].finish()
    for _ in 0..<200 { await Task.yield() }
    #expect(finished.ids == [7, 7, 7, 7])
}

/// A new account's run: once when its test ends, once more when the switch it turned on in the background is done.
@MainActor @Test(.timeLimit(.minutes(1))) func newAccountRunCallsOnFinishedAfterItsBackgroundSwitch() async throws {
    let source = FinishSource(), finished = Finished()
    let writer = FinishWriter(generation: source.generation)
    let center = makeCenter(source, finished, writer: writer)
    let newAccount = AccountTestTarget(account: UpstreamAccount(id: 13, name: "Claude-04", platform: "anthropic", type: "apikey", schedulable: false),
                                       platformName: "Anthropic")
    let run = try #require(center.startNewAccountTest(newAccount, model: nil, status: .paused, writer: writer, opener: nil))
    await settle { source.streams.count == 1 }
    center.detachNewAccountTest(13)
    let passed = AccountTestEvent(type: "test_result", data: AccountTestResult(
        success: true, firstTokenMs: 1210, totalMs: 3420, upstreamStatus: 200, account: .init(status: "active", schedulable: false),
        recovery: .init(clearedError: false, clearedRateLimit: false)))
    source.streams[0].yield(passed); source.streams[0].finish()
    await settle { finished.ids.count == 2 }
    await run.settled()
    #expect(finished.ids == [13, 13] && finished.sentWhenCalled == [0, 1] && run.phase == .passed)
}

@MainActor @Test(.timeLimit(.minutes(1))) func cancelAllCallsNoOnFinished() async {
    let source = FinishSource(), finished = Finished()
    let center = makeCenter(source, finished)
    center.start(target(), model: nil, opener: nil)
    await settle { source.streams.count == 1 }
    center.cancelAll()
    for _ in 0..<200 { await Task.yield() }
    #expect(finished.ids.isEmpty)
}
