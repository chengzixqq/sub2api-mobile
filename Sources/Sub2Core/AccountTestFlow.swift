import Foundation

/// The account a test runs against, as read when the sheet opened (20 §4.3 target line and output header).
public struct AccountTestTarget: Sendable {
    public let account: UpstreamAccount
    public let platformName: String
    public init(account: UpstreamAccount, platformName: String) { self.account = account; self.platformName = platformName }
    public var id: Int { account.id }
    public var name: String { account.name }
    public var credential: AccountTestPresentation.CredentialKind { .init(accountType: account.type) }
}

/// Why a test never reached the upstream (20 §4.5 流打开失败, 00 §2.6.3, §2.7.2).
public enum AccountTestStartFailure: Sendable, Equatable {
    case readOnly
    /// The security sheet was closed: the user starts again by hand.
    case cancelled
    /// 429 ACCOUNT_TEST_BUSY: not retried before `retryAfter` seconds.
    case busy(retryAfter: Int)
    /// The catalog's reason, never the server's message (00 §3.4).
    case failed(String)

    public static let readOnlyLabel = "只读令牌"
    public static let notStarted = "测试没有开始"
    static let busyReason = "站点同时运行的测试已满，请稍后再试"
    static var readOnlyReason: String { ReasonCatalog.entry(status: 403, reason: "ACCESS_TOKEN_READ_ONLY").message }

    public var message: String {
        switch self {
        case .readOnly: Self.readOnlyReason
        case .cancelled: Self.notStarted
        case .busy: Self.notStarted + "：" + Self.busyReason
        case .failed(let reason): Self.notStarted + "：" + reason
        }
    }
}

/// How one test ended: S2-13's outcome, an interruption nobody could settle, or no start at all (S2D1-01).
public enum AccountTestEnding: Sendable, Equatable {
    case finished(AccountTestOutcome)
    case interrupted
    case notStarted(AccountTestStartFailure)
}

/// The sheet's result area (20 §4.3): title, the line under it, Token 用量 and its buttons.
public struct AccountTestResultContent: Sendable, Equatable {
    public let title: String
    public let detail: String?
    public let usage: String?
    public let tone: Tone
    public let systemImage: String
    public let offersEnableScheduling: Bool
    public let offersRetest: Bool
}

/// The receipt of a test that ended after its sheet closed (20 §4.4).
public struct AccountTestReceiptCopy: Sendable, Equatable {
    public enum Button: Sendable, Equatable {
        case view, retest
        public var title: String { self == .view ? "查看" : "重新测试" }
    }
    public let text: String
    public let systemImage: String
    public let tone: Tone
    public let button: Button?
}

/// 20 §4.4–§4.6 decisions of the test task, on top of AccountTestPresentation's wording.
public enum AccountTestFlow {
    /// test-runs are polled every 3 seconds in the foreground; a missing manual record is looked for once more after as long.
    public static let pollInterval: Duration = .seconds(3)
    public static let maxPollFailures = 10
    public static let notice = "测试会向上游发送一次真实请求，可能产生少量费用"
    private static let warning = "exclamationmark.triangle"

    public static func content(_ ending: AccountTestEnding, credential: AccountTestPresentation.CredentialKind) -> AccountTestResultContent {
        switch ending {
        case .finished(let outcome):
            let recovery = AccountTestPresentation.recoveryNote(outcome)
            return AccountTestResultContent(title: AccountTestPresentation.headline(outcome),
                                            detail: recovery?.text ?? AccountTestPresentation.failureNote(outcome, credential: credential),
                                            usage: AccountTestPresentation.usageText(outcome), tone: outcome.passed ? .ok : .critical,
                                            systemImage: outcome.passed ? "checkmark.circle.fill" : "xmark.octagon.fill",
                                            offersEnableScheduling: recovery?.offersEnableScheduling ?? false, offersRetest: false)
        case .interrupted:
            return AccountTestResultContent(title: AccountTestPresentation.interruptedText, detail: nil, usage: nil, tone: .caution,
                                            systemImage: warning, offersEnableScheduling: false, offersRetest: true)
        case .notStarted(.readOnly):
            return AccountTestResultContent(title: AccountTestStartFailure.readOnlyLabel, detail: AccountTestStartFailure.readOnlyReason,
                                            usage: nil, tone: .neutral, systemImage: "lock", offersEnableScheduling: false, offersRetest: false)
        case .notStarted(let failure):
            return AccountTestResultContent(title: failure.message, detail: nil, usage: nil, tone: .caution, systemImage: warning,
                                            offersEnableScheduling: false, offersRetest: true)
        }
    }

    /// nil when there is nothing to say: the user closed the security sheet themselves.
    public static func receipt(_ ending: AccountTestEnding, name: String) -> AccountTestReceiptCopy? {
        switch ending {
        case .finished(let outcome):
            return outcome.passed ? AccountTestReceiptCopy(text: "「\(name)」测试通过", systemImage: "checkmark.circle", tone: .ok, button: .view)
                : AccountTestReceiptCopy(text: "「\(name)」测试未通过", systemImage: "xmark.octagon", tone: .critical, button: .view)
        case .interrupted:
            return AccountTestReceiptCopy(text: AccountTestPresentation.interruptedText, systemImage: warning, tone: .caution, button: .retest)
        case .notStarted(.cancelled): return nil
        case .notStarted(.readOnly):
            return AccountTestReceiptCopy(text: AccountTestStartFailure.readOnlyReason, systemImage: warning, tone: .critical, button: nil)
        case .notStarted(let failure):
            let isBusy = if case .busy = failure { true } else { false }
            return AccountTestReceiptCopy(text: failure.message, systemImage: warning, tone: isBusy ? .caution : .critical,
                                          button: isBusy ? nil : .retest)
        }
    }

    /// 00 §2.7.2: after ACCOUNT_TEST_BUSY, 重新测试 waits out Retry-After; whole seconds left, rounded up.
    public static func retryWait(_ ending: AccountTestEnding, endedAt: Date, now: Date) -> Int {
        guard case .notStarted(.busy(let seconds)) = ending else { return 0 }
        return max(0, Int(endedAt.addingTimeInterval(TimeInterval(seconds)).timeIntervalSince(now).rounded(.up)))
    }
    public static func retryTitle(remainingSeconds: Int) -> String { remainingSeconds > 0 ? "\(remainingSeconds) 秒后重新测试" : "重新测试" }

    public static func startFailure(_ error: any Error) -> AccountTestStartFailure {
        if error is CancellationError { return .cancelled }
        guard let api = error as? APIError else { return .failed(error.localizedDescription) }
        if api.securityOutcome == .cancelled { return .cancelled }
        switch (api.statusCode, api.reason) {
        case (403?, "ACCESS_TOKEN_READ_ONLY"?): return .readOnly
        case (429?, "ACCOUNT_TEST_BUSY"?): return .busy(retryAfter: api.retryAfter ?? RetryAfter.rateLimitDefault)
        default: return .failed(api.localizedDescription)
        }
    }
    /// A vendor workspace is refused `:id/test-runs` with a plain 403 FORBIDDEN although `/admin/me` lists the capability.
    public static func fallsBackToStream(_ error: any Error) -> Bool {
        guard let api = error as? APIError else { return false }
        return api.statusCode == 403 && api.reason == "FORBIDDEN"
    }
    public static func isMissingRun(_ error: any Error) -> Bool {
        guard let api = error as? APIError else { return false }
        return api.statusCode == 404 && api.reason == AccountTestRunReason.notFound
    }
    /// The latest run belongs to this attempt and is over, so looking again would not tell more (20 §4.4).
    public static func concludes(_ run: AccountTestRun?, attemptStartedAt: Date) -> Bool {
        guard let run, run.isFinished, run.status != .unknown, let started = run.startedAt else { return false }
        return started >= attemptStartedAt.addingTimeInterval(-AccountTestPresentation.interruptionTolerance)
    }

    /// 20 §4.4: test_result's `account` replaces the status fields; the rest of the account waits for `GET :id`.
    public static func applying(_ state: AccountTestResult.AccountState, to account: UpstreamAccount) -> UpstreamAccount {
        var updated = account
        updated.status = state.status
        updated.schedulable = state.schedulable
        updated.rateLimitResetAt = state.rateLimitResetAt.map(ServerTime.utcTimestamp)
        updated.tempUnschedulableUntil = state.tempUnschedulableUntil.map(ServerTime.utcTimestamp)
        guard state.status == "error" else {
            updated.errorMessage = nil; updated.errorSummary = nil; updated.errorKind = nil; updated.errorStatusCode = nil; updated.errorAt = nil
            return updated
        }
        updated.errorSummary = state.errorSummary ?? account.errorSummary
        updated.errorKind = state.errorKind ?? account.errorKind
        return updated
    }

    /// What a finished run adds to the output: its answer, or “✕ {error}”; both redacted.
    public static func outputEvents(for run: AccountTestRun) -> [AccountTestEvent] {
        switch run.status {
        case .success: run.sanitizedResponseText.map { [AccountTestEvent(type: "content", content: $0)] } ?? []
        case .failed: [AccountTestEvent(type: "error", message: run.sanitizedErrorText ?? run.errorSummary)]
        default: []
        }
    }
}
