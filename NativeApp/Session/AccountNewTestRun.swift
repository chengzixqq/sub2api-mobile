import Foundation
import Observation
import Sub2Core

/// What a new account's test needs once it has ended (AppModel+Accounts, S2-06's members): the read for its version and state,
/// and the switch, which carries the generation of the session the account was created in (S2D1-05).
@MainActor protocol AccountNewScheduleWriter: AnyObject {
    var accountWriteSession: AccountWriteSession? { get }
    func setAccountSchedulable(id: Int, enabled: Bool, idempotencyKey: UUID?, generation: UUID) async throws -> WriteOutcome<UpstreamAccount>
    func accountWithVersion(id: Int) async throws -> VersionedAccount
}

/// 20 §7.4-1 / -4: a new account's test, then the switch on. AccountTestCenter holds it, so closing the form does not stop it
/// (20 §4.4). The end reads the account (its version for the next PATCH, and whether the test left it in error); a pass turns
/// scheduling on, keyed with admin.idempotent_writes at that moment. An unknown answer is read back, and 重试启用 keeps the key
/// unless the server refused for certain. Detached, the end is a receipt whose 查看 / 处理 opens the account. Nothing is written
/// or said once the session has changed or AppModel is gone.
@MainActor @Observable
final class AccountNewTestRun {
    enum Phase: Equatable, Sendable { case testing, enabling, passed, enableFailed(String?), failed, interrupted, notStarted(String) }

    let accountID: Int
    let generation: UUID
    private(set) var name: String
    private(set) var phase: Phase = .testing
    private(set) var verdict: AccountNewTestVerdict?
    /// Where the account stands while scheduling is off: paused, or in error after a failure the backend marked.
    private(set) var status: AccountNewScheduleStatus
    /// `GET :id` after the test.
    private(set) var latest: VersionedAccount?
    private(set) var isDetached = false
    @ObservationIgnored private var credential: AccountTestPresentation.CredentialKind
    @ObservationIgnored private weak var writer: (any AccountNewScheduleWriter)?
    @ObservationIgnored private let receipts: ReceiptCenter
    @ObservationIgnored private let opener: AccountTestCenter.Opener?
    @ObservationIgnored private let makeKey: @MainActor () -> UUID
    @ObservationIgnored private let onSettled: @MainActor (Int) -> Void
    @ObservationIgnored private var followUp: Task<Void, Never>?
    @ObservationIgnored private var enableKey: UUID?
    /// The last switch may have run: 重试启用 goes under the same key (00 §2.5.3).
    @ObservationIgnored private var reusesKey = false

    init(target: AccountTestTarget, generation: UUID, status: AccountNewScheduleStatus, writer: any AccountNewScheduleWriter, receipts: ReceiptCenter,
         opener: AccountTestCenter.Opener?, makeKey: @escaping @MainActor () -> UUID = { UUID() }, onSettled: @escaping @MainActor (Int) -> Void) {
        accountID = target.id; name = target.name; credential = target.credential
        self.generation = generation; self.status = status; self.writer = writer; self.receipts = receipts; self.opener = opener
        self.makeKey = makeKey; self.onSettled = onSettled
    }

    var isSettled: Bool { phase != .testing && phase != .enabling }
    var isPassed: Bool { phase == .passed }

    /// Another model, 重新测试, or the test after 保存修改, all after a test that did not pass: the status it left stays.
    func restart(_ target: AccountTestTarget) {
        cancel()
        name = target.name; credential = target.credential
        phase = .testing; verdict = nil; isDetached = false
    }
    /// AccountTestCenter's end of the test.
    func testEnded(_ ending: AccountTestEnding) {
        guard phase == .testing else { return }
        switch ending {
        case .finished(let outcome):
            let verdict = AccountNewTestVerdict(outcome: outcome, credential: credential)
            self.verdict = verdict
            followUp = Task { await self.conclude(verdict, switchedOn: outcome.account?.schedulable == true) }
        case .interrupted: settle(.interrupted)
        case .notStarted(let failure): settle(.notStarted(failure.message))
        }
    }
    func retryEnable() {
        guard case .enableFailed = phase, isCurrent else { return }
        if !reusesKey { enableKey = newKey() }
        followUp = Task { await self.enable() }
    }
    /// The form closed: a run still going ends in a receipt (only a test says it went on in the background); an ended one is done.
    func detach() {
        guard !isDetached else { return }
        guard !isSettled else { return onSettled(accountID) }
        isDetached = true
        if phase == .testing { show(AccountNewTestPresentation.movedToBackground(name: name)) }
    }
    func cancel() {
        followUp?.cancel()
        followUp = nil
    }
    /// Tests: the read and the switch after the test.
    func settled() async { await followUp?.value }

    // MARK: - After the test

    private var isCurrent: Bool { !Task.isCancelled && writer?.accountWriteSession?.generation == generation }

    private func conclude(_ verdict: AccountNewTestVerdict, switchedOn: Bool) async {
        let fresh = try? await writer?.accountWithVersion(id: accountID)
        guard isCurrent else { return cancel() }
        if let fresh { latest = fresh }
        status = AccountNewTestPresentation.status(after: verdict, readBack: fresh?.account.status, previous: status)
        guard verdict.passed else { return settle(.failed) }
        guard !switchedOn, fresh?.account.schedulable != true else { return settle(.passed) }
        enableKey = newKey()
        await enable()
    }
    private func enable() async {
        guard let writer else { return cancel() }
        phase = .enabling
        do {
            let outcome = try await writer.setAccountSchedulable(id: accountID, enabled: true, idempotencyKey: enableKey, generation: generation)
            guard isCurrent else { return cancel() }
            latest = VersionedAccount(account: outcome.value, etag: latest?.etag)
            settle(.passed)
        } catch {
            guard isCurrent else { return cancel() }
            await enableFailed(error)
        }
    }
    /// 20 §5.5: a switch that may have run is read back, on reading true it is done; a refusal takes a new key next time.
    private func enableFailed(_ error: any Error) async {
        switch AccountActionCopy.disposition(of: error) {
        case .readBack:
            reusesKey = true
            do {
                let fresh = try await writer?.accountWithVersion(id: accountID)
                guard isCurrent else { return cancel() }
                if let fresh { latest = fresh }
                if fresh?.account.schedulable == true { return settle(.passed) }
                settle(.enableFailed(AccountActionCopy.reason(for: error)))
            } catch {
                guard isCurrent else { return cancel() }
                settle(.enableFailed(AccountActionCopy.unconfirmed))
            }
        case .cancelled:
            reusesKey = true
            settle(.enableFailed(nil))
        case .reconfirm, .versionConflict, .missing, .failed:
            reusesKey = false
            settle(.enableFailed(AccountActionCopy.reason(for: error)))
        }
    }
    private func settle(_ phase: Phase) {
        self.phase = phase
        followUp = nil
        guard isDetached else { return }
        if let result { show(AccountNewTestPresentation.background(name: name, result: result)) }
        onSettled(accountID)
    }
    private var result: AccountNewBackgroundResult? {
        switch phase {
        case .passed: .passed
        case .enableFailed: .enableFailed
        case .failed: .failed(status)
        case .interrupted, .notStarted: .incomplete
        case .testing, .enabling: nil
        }
    }
    private func newKey() -> UUID? { writer?.accountWriteSession?.idempotentWrites == true ? makeKey() : nil }
    private func show(_ copy: AccountNewTestReceipt) {
        let id = accountID, opener = opener
        let action = copy.button.map { button in ReceiptAction(title: button.title) { opener?(id) } }
        receipts.show(Receipt(text: copy.text, systemImage: copy.systemImage, tone: copy.tone, action: action))
    }
}
