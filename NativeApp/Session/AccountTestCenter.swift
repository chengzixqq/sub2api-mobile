import Foundation
import Observation
import Sub2Core

/// What a test reads of the session when it starts.
struct AccountTestSession: Sendable, Equatable {
    let generation: UUID
    /// accounts.test_result: only test_result ends the stream.
    let supportsTestResult: Bool
    /// accounts.test_runs: 重新测试 and the interruption check use test-runs.
    let supportsTestRuns: Bool
    let isReadOnlyToken: Bool
}

/// The reads and writes of a test (AppModel+Accounts). Starting one is a write and carries the session's generation (S2D1-05).
@MainActor protocol AccountTestSource: AnyObject {
    var accountTestSession: AccountTestSession? { get }
    var isSuspended: Bool { get }
    func serverNow() -> Date
    func accountWithVersion(id: Int) async throws -> VersionedAccount
    func testAccountStream(id: Int, model: String?, generation: UUID) async throws -> AsyncThrowingStream<AccountTestEvent, any Error>
    func startAccountTestRun(id: Int, model: String?, generation: UUID) async throws -> AccountTestRunStart
    func latestAccountTestRun(id: Int) async throws -> AccountTestRun?
    func accountTestRun(runID: String) async throws -> AccountTestRun
}

/// The result's “启用调度” (20 §5); AccountActions in the App, so its receipt and 撤销 outlive the sheet.
@MainActor protocol AccountTestScheduling: AnyObject {
    func enableScheduling(_ account: UpstreamAccount) async
}

extension AccountActions: AccountTestScheduling {
    func enableScheduling(_ account: UpstreamAccount) async { await setSchedulable(account, enabled: true) }
}

/// UIApplication's background task, given by the App so this file stays free of UIKit; nil is no task.
struct AccountTestBackgroundActivity: Sendable {
    let begin: @MainActor @Sendable (_ onExpire: @escaping @MainActor @Sendable () -> Void) -> Int?
    let end: @MainActor @Sendable (Int) -> Void
    static let none = AccountTestBackgroundActivity(begin: { _ in nil }, end: { _ in })
}

/// One account's test as the sheet draws it.
struct AccountTestState: Sendable {
    enum Phase: Sendable, Equatable {
        /// `polling`: an async run, read every 3 seconds.
        case running(polling: Bool)
        /// `at`: site time, for ACCOUNT_TEST_BUSY's wait.
        case ended(AccountTestEnding, at: Date)
    }
    let ticket: UUID
    let target: AccountTestTarget
    let model: String?
    /// Site time just before the request, for the interruption check (20 §0.6).
    let startedAt: Date
    var transcript: AccountTestTranscript
    var phase: Phase
    /// The sheet closed: the end shows a receipt instead.
    var isDetached: Bool

    var isRunning: Bool { if case .running = phase { true } else { false } }
    var ending: AccountTestEnding? { if case .ended(let ending, _) = phase { ending } else { nil } }
    /// test_start's model once it arrived.
    var shownModel: String? { transcript.model ?? model }
    var lines: [String] {
        AccountTestPresentation.headerLines(platformName: target.platformName, accountName: target.name, model: shownModel)
            + transcript.displayLines
    }
    var content: AccountTestResultContent? { ending.map { AccountTestFlow.content($0, credential: target.credential) } }
    /// The account as the test left it, for “启用调度”.
    var accountAfterTest: UpstreamAccount {
        guard case .finished(let outcome)? = ending, let state = outcome.account else { return target.account }
        return AccountTestFlow.applying(state, to: target.account)
    }
}

/// What a finished test or its “启用调度” changed; the detail merges it and reads the account again (20 §4.4).
struct AccountTestCompletion: Sendable {
    enum Change: Sendable {
        /// The status fields after the test; nil when unknown.
        case tested(AccountTestResult.AccountState?)
        case written(UpstreamAccount)
    }
    let id: UUID
    let change: Change
}

/// 20 §4.4: the session's account tests, one per account. Closing the sheet does not stop a test: it ends in a receipt with
/// “查看”. A stream cut before test_result is settled from test-runs/latest in the foreground; 重新测试 starts an async run with
/// accounts.test_runs and polls it every 3 seconds while in the foreground. The stream holds a background task (UIKit's, given
/// by the App). Anything that answers after the session changed is dropped. AppModel creates one per session.
@MainActor @Observable
final class AccountTestCenter {
    typealias Opener = @MainActor @Sendable (Int) -> Void
    typealias SchedulingFactory = @MainActor (_ onChange: @escaping @MainActor (UpstreamAccount) -> Void) -> any AccountTestScheduling

    let generation: UUID
    private(set) var states: [Int: AccountTestState] = [:]
    private(set) var completions: [Int: AccountTestCompletion] = [:]
    /// New accounts' tests and the switch after them (S2-20), by account.
    private(set) var newAccountRuns: [Int: AccountNewTestRun] = [:]
    @ObservationIgnored private let source: any AccountTestSource
    @ObservationIgnored private let receipts: ReceiptCenter
    @ObservationIgnored private let makeScheduling: SchedulingFactory
    @ObservationIgnored private let background: AccountTestBackgroundActivity
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var tasks: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var openers: [Int: Opener] = [:]
    @ObservationIgnored private var backgroundTokens: [UUID: Int] = [:]
    @ObservationIgnored private var scheduling: (any AccountTestScheduling)?

    init(generation: UUID, source: any AccountTestSource, receipts: ReceiptCenter, makeScheduling: @escaping SchedulingFactory,
         background: AccountTestBackgroundActivity = .none,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.generation = generation; self.source = source; self.receipts = receipts; self.makeScheduling = makeScheduling
        self.background = background; self.sleep = sleep
    }

    func state(for accountID: Int) -> AccountTestState? { states[accountID] }
    func isRunning(_ accountID: Int) -> Bool { states[accountID]?.isRunning == true }
    func completion(for accountID: Int) -> AccountTestCompletion? { completions[accountID] }

    /// The SSE test. False while this account's test runs, in another session, or with a read-only token (then nothing is sent).
    @discardableResult
    func start(_ target: AccountTestTarget, model: String?, opener: Opener?) -> Bool {
        launch(target, model: model, usesRuns: false, detached: false, opener: opener)
    }
    /// 重新测试: an async run with accounts.test_runs, else the stream.
    @discardableResult
    func retest(_ target: AccountTestTarget, model: String?, opener: Opener?) -> Bool {
        launch(target, model: model, usesRuns: true, detached: false, opener: opener)
    }
    /// The result area's 重新测试 for an ended test: an interruption or a busy site goes to test-runs, a failed start opens the
    /// stream again.
    @discardableResult
    func retry(_ accountID: Int) -> Bool {
        guard let state = states[accountID], let ending = state.ending else { return false }
        return launch(state.target, model: state.model, usesRuns: Self.retriesWithRuns(ending), detached: state.isDetached,
                      opener: openers[accountID])
    }
    func attach(_ accountID: Int) { states[accountID]?.isDetached = false }
    /// The sheet closed: a running test goes on detached, an ended one is forgotten.
    func detach(_ accountID: Int) {
        guard let state = states[accountID] else { return }
        if state.isRunning { states[accountID]?.isDetached = true } else { states[accountID] = nil }
    }
    func enableScheduling(_ account: UpstreamAccount) async {
        guard source.accountTestSession?.generation == generation else { return }
        let actions = scheduling ?? makeScheduling { [weak self] in self?.post($0.id, .written($0)) }
        scheduling = actions
        await actions.enableScheduling(account)
    }
    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        backgroundTokens.values.forEach { background.end($0) }
        backgroundTokens = [:]
        states = [:]; completions = [:]; openers = [:]
        newAccountRuns.values.forEach { $0.cancel() }
        newAccountRuns = [:]
    }

    // MARK: - Running

    private func launch(_ target: AccountTestTarget, model: String?, usesRuns: Bool, detached: Bool, opener: Opener?) -> Bool {
        guard let session = source.accountTestSession, session.generation == generation, !isRunning(target.id) else { return false }
        let id = target.id, ticket = UUID(), polls = usesRuns && session.supportsTestRuns
        tasks[id]?.cancel()
        states[id] = AccountTestState(ticket: ticket, target: target, model: model, startedAt: source.serverNow(),
                                      transcript: AccountTestTranscript(startedAt: .now), phase: .running(polling: polls), isDetached: detached)
        openers[id] = opener
        guard !session.isReadOnlyToken else { end(id, .notStarted(.readOnly)); return false }
        tasks[id] = Task { [weak self] in
            if polls { await self?.runAsync(id, ticket: ticket, session: session) } else { await self?.runStream(id, ticket: ticket, session: session) }
        }
        return true
    }
    private func isCurrent(_ id: Int, _ ticket: UUID) -> Bool {
        !Task.isCancelled && source.accountTestSession?.generation == generation && states[id]?.ticket == ticket
    }

    private func runStream(_ id: Int, ticket: UUID, session: AccountTestSession) async {
        guard let state = states[id] else { return }
        holdBackgroundTask(ticket)
        defer { releaseBackgroundTask(ticket) }
        let stream: AsyncThrowingStream<AccountTestEvent, any Error>
        do { stream = try await source.testAccountStream(id: id, model: state.model, generation: generation) }
        catch {
            guard isCurrent(id, ticket) else { return }
            return end(id, .notStarted(AccountTestFlow.startFailure(error)))
        }
        do {
            for try await event in stream {
                guard isCurrent(id, ticket) else { return }
                states[id]?.transcript.apply(event, at: .now)
            }
        } catch {
            // A cut stream, or CancellationError in this same session: settled below like any other disconnect (S2D1-02).
        }
        guard isCurrent(id, ticket) else { return }
        states[id]?.transcript.finish(at: .now)
        releaseBackgroundTask(ticket)
        await conclude(id, ticket: ticket, session: session)
    }
    /// test_result decides; an old server's verdict is compared with the account read back; anything else was cut short.
    private func conclude(_ id: Int, ticket: UUID, session: AccountTestSession) async {
        guard let state = states[id] else { return }
        let transcript = state.transcript
        if let outcome = transcript.serverOutcome { return end(id, .finished(outcome)) }
        guard transcript.receivedTestResult || !session.supportsTestResult, let passed = transcript.legacyPassed else {
            return await checkInterruption(id, ticket: ticket, session: session)
        }
        let after = await readBack(id)
        guard isCurrent(id, ticket) else { return }
        let outcome = AccountTestOutcome.legacy(passed: passed, timing: transcript.localTiming, before: .init(account: state.target.account),
                                                after: after, now: source.serverNow(), errorText: transcript.errorText)
        end(id, .finished(outcome))
    }
    /// 20 §4.4: in the foreground, the latest run that started with this attempt; looked for once more 3 seconds later.
    private func checkInterruption(_ id: Int, ticket: UUID, session: AccountTestSession) async {
        guard session.supportsTestRuns, let startedAt = states[id]?.startedAt else { return end(id, .interrupted) }
        guard await waitForForeground(id, ticket) else { return }
        var latest = try? await source.latestAccountTestRun(id: id)
        guard isCurrent(id, ticket) else { return }
        if !AccountTestFlow.concludes(latest, attemptStartedAt: startedAt) {
            try? await self.sleep(AccountTestFlow.pollInterval)
            guard isCurrent(id, ticket), await waitForForeground(id, ticket) else { return }
            latest = try? await source.latestAccountTestRun(id: id)
            guard isCurrent(id, ticket) else { return }
        }
        let settles = AccountTestFlow.concludes(latest, attemptStartedAt: startedAt) && (latest?.status == .success || latest?.status == .failed)
        let after: AccountTestResult.AccountState? = if settles { await readBack(id) } else { nil }
        guard isCurrent(id, ticket) else { return }
        switch AccountTestPresentation.interruptionCheck(latest: latest, attemptStartedAt: startedAt, after: after) {
        case .settled(let outcome):
            if let latest { append(AccountTestFlow.outputEvents(for: latest), to: id) }
            end(id, .finished(outcome))
        case .interrupted: end(id, .interrupted)
        }
    }

    private func runAsync(_ id: Int, ticket: UUID, session: AccountTestSession) async {
        guard let state = states[id] else { return }
        let runID: String
        do {
            switch try await source.startAccountTestRun(id: id, model: state.model, generation: generation) {
            case .started(let run): runID = run.runID
            case .alreadyRunning(let running): runID = running
            }
        } catch {
            guard isCurrent(id, ticket) else { return }
            guard AccountTestFlow.fallsBackToStream(error) else { return end(id, .notStarted(AccountTestFlow.startFailure(error))) }
            states[id]?.phase = .running(polling: false)
            return await runStream(id, ticket: ticket, session: session)
        }
        guard isCurrent(id, ticket) else { return }
        await poll(id, runID: runID, ticket: ticket)
    }
    /// 20 §4.6: every 3 seconds in the foreground; a tick while suspended sends nothing, so the first one back reads it.
    private func poll(_ id: Int, runID: String, ticket: UUID) async {
        var failures = 0
        while true {
            do { try await self.sleep(AccountTestFlow.pollInterval) } catch { return }
            guard isCurrent(id, ticket) else { return }
            guard !source.isSuspended else { continue }
            do {
                let run = try await source.accountTestRun(runID: runID)
                guard isCurrent(id, ticket) else { return }
                failures = 0
                if run.isFinished { return await finishRun(id, run: run, ticket: ticket) }
            } catch {
                guard isCurrent(id, ticket) else { return }
                failures += 1
                if AccountTestFlow.isMissingRun(error) || failures >= AccountTestFlow.maxPollFailures { return end(id, .interrupted) }
            }
        }
    }
    /// A run has no switch state: the account read back tells whether it still pauses scheduling.
    private func finishRun(_ id: Int, run: AccountTestRun, ticket: UUID) async {
        let after: AccountTestResult.AccountState? = if run.status == .success || run.status == .failed { await readBack(id) } else { nil }
        guard isCurrent(id, ticket) else { return }
        append(AccountTestFlow.outputEvents(for: run), to: id)
        end(id, AccountTestOutcome(run: run, after: after).map(AccountTestEnding.finished) ?? .interrupted)
    }

    // MARK: - Helpers

    private func end(_ id: Int, _ ending: AccountTestEnding) {
        guard var state = states[id], state.isRunning else { return }
        state.phase = .ended(ending, at: source.serverNow())
        tasks[id] = nil
        releaseBackgroundTask(state.ticket)
        switch ending {
        case .finished(let outcome): post(id, .tested(outcome.account))
        case .interrupted: post(id, .tested(nil))
        case .notStarted: break
        }
        // A new account's run says how it ended itself (S2-20).
        if let run = newAccountRuns[id] {
            states[id] = state.isDetached ? nil : state
            return run.testEnded(ending)
        }
        guard state.isDetached else { states[id] = state; return }
        states[id] = nil
        showReceipt(ending, state: state)
    }
    private func showReceipt(_ ending: AccountTestEnding, state: AccountTestState) {
        guard let copy = AccountTestFlow.receipt(ending, name: state.target.name) else { return }
        let target = state.target, model = state.model, opener = openers[target.id]
        let action: ReceiptAction? = switch copy.button {
        case .view?: ReceiptAction(title: copy.button?.title ?? "") { opener?(target.id) }
        case .retest?: ReceiptAction(title: copy.button?.title ?? "") { [weak self] in
            _ = self?.launch(target, model: model, usesRuns: Self.retriesWithRuns(ending), detached: true, opener: opener)
        }
        case nil: nil
        }
        receipts.show(Receipt(text: copy.text, systemImage: copy.systemImage, tone: copy.tone, action: action))
    }
    private static func retriesWithRuns(_ ending: AccountTestEnding) -> Bool {
        switch ending {
        case .interrupted, .notStarted(.busy): true
        default: false
        }
    }
    private func post(_ id: Int, _ change: AccountTestCompletion.Change) {
        completions[id] = AccountTestCompletion(id: UUID(), change: change)
    }
    private func append(_ events: [AccountTestEvent], to id: Int) {
        for event in events { states[id]?.transcript.apply(event, at: .now) }
        states[id]?.transcript.finish(at: .now)
    }
    private func readBack(_ id: Int) async -> AccountTestResult.AccountState? {
        guard let versioned = try? await source.accountWithVersion(id: id) else { return nil }
        return AccountTestResult.AccountState(account: versioned.account)
    }
    /// False once the test no longer belongs here.
    private func waitForForeground(_ id: Int, _ ticket: UUID) async -> Bool {
        while source.isSuspended {
            try? await self.sleep(AccountTestFlow.pollInterval)
            guard isCurrent(id, ticket) else { return false }
        }
        return isCurrent(id, ticket)
    }
    private func holdBackgroundTask(_ ticket: UUID) {
        guard backgroundTokens[ticket] == nil,
              let token = background.begin({ [weak self] in self?.releaseBackgroundTask(ticket) }) else { return }
        backgroundTokens[ticket] = token
    }
    private func releaseBackgroundTask(_ ticket: UUID) {
        guard let token = backgroundTokens.removeValue(forKey: ticket) else { return }
        background.end(token)
    }
}

// MARK: - 新建账号（S2-20）

extension AccountTestCenter {
    func newAccountRun(for accountID: Int?) -> AccountNewTestRun? { accountID.flatMap { newAccountRuns[$0] } }
    /// 20 §7.4-1: the new account's test over the stream, its run made (or restarted, keeping the status the last test left) before
    /// it starts. nil in another session or while this account's test runs.
    @discardableResult
    func startNewAccountTest(_ target: AccountTestTarget, model: String?, status: AccountNewScheduleStatus, writer: any AccountNewScheduleWriter,
                             opener: Opener?, makeKey: @escaping @MainActor () -> UUID = { UUID() }) -> AccountNewTestRun? {
        guard source.accountTestSession?.generation == generation, !isRunning(target.id) else { return nil }
        let run = newAccountRuns[target.id] ?? AccountNewTestRun(target: target, generation: generation, status: status, writer: writer, receipts: receipts,
                                                                 opener: opener, makeKey: makeKey,
                                                                 onSettled: { [weak self] id in self?.newAccountRuns[id] = nil })
        run.restart(target)
        newAccountRuns[target.id] = run
        start(target, model: model, opener: opener)
        return run
    }
    /// The form closed while the test or the switch is out: it goes on, and its end is a receipt (20 §7.4-4).
    func detachNewAccountTest(_ accountID: Int) {
        detach(accountID)
        newAccountRuns[accountID]?.detach()
    }
    /// The form dealt with the ended run (完成, 保留, 停用, 删除).
    func endNewAccountTest(_ accountID: Int) {
        newAccountRuns.removeValue(forKey: accountID)?.cancel()
        detach(accountID)
    }
}

extension AppRouter {
    /// A receipt's “查看”: the account's detail on the current tab, unless it is already on top.
    func showAccount(id: Int) {
        if case .account(let top, _, _)? = path(for: selectedTab).last, top == id { return }
        push(.account(id: id))
    }
}
