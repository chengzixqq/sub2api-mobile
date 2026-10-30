import Foundation

/// A finished test as the new-account sheet reads it (20 §7.3): the one place S2-13's outcome becomes this sheet's words.
public struct AccountNewTestVerdict: Sendable, Equatable {
    public let passed: Bool
    /// test_result's marked.error (an old server's: the snapshots compared).
    public let markedError: Bool
    /// The account's status after the test; nil when unknown.
    public let statusAfter: String?
    public let clearedError: Bool
    /// 7.3's reason of a failure; nil when passed.
    public let reason: String?
    /// “上游返回 {code} · {error}”, redacted.
    public let detailLine: String?
    /// “首字 Xs · 总耗时 Ys[ · 本机计时]”.
    public let timing: String?

    public init(passed: Bool, markedError: Bool = false, statusAfter: String? = nil, clearedError: Bool = false, reason: String? = nil,
                detailLine: String? = nil, timing: String? = nil) {
        self.passed = passed; self.markedError = markedError; self.statusAfter = statusAfter; self.clearedError = clearedError
        self.reason = reason; self.detailLine = detailLine; self.timing = timing
    }
    public init(outcome: AccountTestOutcome, credential: AccountTestPresentation.CredentialKind) {
        let reason = outcome.passed ? nil
            : AccountTestPresentation.failureReason(errorKind: outcome.errorKind, upstreamStatus: outcome.upstreamStatus, credential: credential)
        self.init(passed: outcome.passed, markedError: outcome.marked?.error == true, statusAfter: outcome.account?.status,
                  clearedError: outcome.recovery?.clearedError == true, reason: reason,
                  detailLine: AccountTestPresentation.failureDetailLine(outcome), timing: outcome.timing.map(AccountTestPresentation.timingText))
    }
    /// “测试未通过 · {原因}”.
    public var headline: String { reason.map { "测试未通过 · " + $0 } ?? (passed ? "测试通过" : "测试未通过") }
}

/// What the test sheet draws (20 §7.3). It opens once the account exists, so the create row is done; the write row is the
/// retry's save. The create and stop stages come from AccountNewSubmission, the test and switch from AccountNewTestRun.
public struct AccountNewTestSnapshot: Sendable, Equatable {
    public enum Write: Sendable, Equatable { case running, done, unchanged, failed(String) }
    public enum Pause: Sendable, Equatable { case running, done, unconfirmed }
    public enum Test: Sendable, Equatable {
        case waiting
        /// The version and the models are read before the test starts.
        case preparing
        case running
        case finished(AccountNewTestVerdict)
        case interrupted
        case notStarted(String)
    }
    public enum Enable: Sendable, Equatable { case waiting, running, done, failed(String?) }

    public var accountID: Int
    /// 保存并重新测试 / 重新测试: the first row is “保存修改”.
    public var isRetry: Bool
    public var write: Write
    public var pause: Pause
    public var test: Test
    public var enable: Enable
    /// nil reads “默认模型”.
    public var model: String?
    /// .paused or .error while scheduling is off.
    public var status: AccountNewScheduleStatus

    public init(accountID: Int, isRetry: Bool = false, write: Write = .done, pause: Pause = .done, test: Test = .waiting, enable: Enable = .waiting,
                model: String? = nil, status: AccountNewScheduleStatus = .paused) {
        self.accountID = accountID; self.isRetry = isRetry; self.write = write; self.pause = pause; self.test = test; self.enable = enable
        self.model = model; self.status = status
    }
    /// A request is out: the sheet cannot be swiped away and has no 关闭.
    public var isBusy: Bool {
        write == .running || pause == .running || test == .preparing || test == .running || enable == .running
    }
    /// Only a running test goes on in the background (4.4).
    public var allowsBackground: Bool { test == .running }
    public var isPassed: Bool { enable == .done }
    var testEndedWithoutPass: Bool {
        switch test {
        case .finished(let verdict): !verdict.passed
        case .interrupted, .notStarted: true
        case .waiting, .preparing, .running: false
        }
    }
    var verdict: AccountNewTestVerdict? { if case .finished(let verdict) = test { verdict } else { nil } }
}

public enum AccountNewTestStageState: String, Sendable { case waiting, running, done, failed, off }

/// One of the four progress rows.
public struct AccountNewTestStageRow: Sendable, Equatable, Identifiable {
    public enum Stage: String, Sendable { case create, save, pause, test, enable }
    public let stage: Stage
    public let title: String
    public let state: AccountNewTestStageState
    public let meta: String?
    /// The save's failure reason, under the row.
    public let detail: String?
    /// The test row's model can be tapped to test again with another.
    public let offersModelChange: Bool
    public var id: Stage { stage }
    init(_ stage: Stage, _ title: String, _ state: AccountNewTestStageState, meta: String? = nil, detail: String? = nil, offersModelChange: Bool = false) {
        self.stage = stage; self.title = title; self.state = state; self.meta = meta; self.detail = detail; self.offersModelChange = offersModelChange
    }
}

/// The result under the rows and its buttons; `destructive` is the last, quiet red “删除账号…”.
public struct AccountNewTestResultBlock: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case passed, enableFailed, failed, incomplete, pauseUnconfirmed, writeFailed }
    public enum Button: String, Sendable, CaseIterable { case viewAccount, done, retryEnable, editAndRetry, retest, keep, saveInactive, delete, repause, back }
    public let kind: Kind
    public let tone: Tone
    public let systemImage: String
    public let title: String
    public let detail: String?
    /// The raw failure, monospaced.
    public let mono: String?
    public let primary: Button?
    public let secondary: [Button]
    public let destructive: Button?
    public let footnote: String?
    init(_ kind: Kind, _ tone: Tone, _ systemImage: String, _ title: String, detail: String? = nil, mono: String? = nil, primary: Button?,
         secondary: [Button] = [], destructive: Button? = nil, footnote: String? = nil) {
        self.kind = kind; self.tone = tone; self.systemImage = systemImage; self.title = title; self.detail = detail; self.mono = mono
        self.primary = primary; self.secondary = secondary; self.destructive = destructive; self.footnote = footnote
    }
}

public struct AccountNewTestReceipt: Sendable, Equatable {
    public enum Button: Sendable, Equatable {
        case view, resolve
        public var title: String { self == .view ? "查看" : "处理" }
    }
    public let text: String
    public let systemImage: String
    public let tone: Tone
    public let button: Button?
}

/// How a test that went on in the background ended (20 §7.4-4).
public enum AccountNewBackgroundResult: Sendable, Equatable { case passed, enableFailed, failed(AccountNewScheduleStatus), incomplete }

/// “账号「{name}」已创建，怎么处理？”: 保存为停用 / {keepTitle} / 删除账号… / 继续修改.
public struct AccountNewResolveDialog: Sendable, Equatable {
    public let title: String
    public let message: String
    public let keepTitle: String
    public let cancelTitle: String
}

public struct AccountNewTestDockText: Sendable, Equatable {
    public let title: String
    public let detail: String
}

public struct AccountNewTestOutputSummary: Sendable, Equatable {
    public let last: String
    public let count: String
}

/// 20 §7.3 / §7.4 wording of the test sheet and what follows it. Never the server's message (00 §3.4).
public enum AccountNewTestPresentation {
    public static let notice = "测试会向上游发一次真实请求，可能产生少量费用。"
    public static let backgroundTitle = "后台继续"
    public static let closeTitle = "关闭"
    public static let saveInactiveVerb = "保存为停用"

    public static func sheetTitle(_ s: AccountNewTestSnapshot) -> String {
        AccountNewFlow.dockActionTitle(isCreated: s.isRetry, hasChanges: s.write != .unchanged)
    }
    public static func rows(_ s: AccountNewTestSnapshot) -> [AccountNewTestStageRow] { [writeRow(s), pauseRow(s), testRow(s), enableRow(s)] }

    public static func resultBlock(_ s: AccountNewTestSnapshot) -> AccountNewTestResultBlock? {
        if s.isRetry, case .failed = s.write {
            return AccountNewTestResultBlock(.writeFailed, .critical, "xmark.octagon.fill", "修改没有保存到账号 #\(s.accountID)", primary: .back)
        }
        if !s.isRetry, s.pause == .unconfirmed {
            return AccountNewTestResultBlock(.pauseUnconfirmed, .critical, "exclamationmark.octagon.fill", "停止调度没有确认 · 结果待核对",
                                             detail: "账号 #\(s.accountID) 已创建，可能正在参与调度。凭据还没验证，可能已经在接收请求。重试一次停止调度，成功后自动开始测试。",
                                             primary: .repause, destructive: .delete)
        }
        switch s.enable {
        case .done:
            let detail = [s.verdict?.clearedError == true ? "错误状态已自动清除。" : nil, s.verdict?.timing].compactMap { $0 }.joined()
            return AccountNewTestResultBlock(.passed, .ok, "checkmark.circle.fill", "测试通过 · 已启用调度", detail: detail.isEmpty ? nil : detail,
                                             primary: .done, secondary: [.viewAccount])
        case .failed(let reason):
            return AccountNewTestResultBlock(.enableFailed, .caution, "exclamationmark.triangle.fill", "测试通过 · 启用调度没有成功", detail: reason,
                                             primary: .retryEnable, secondary: [.viewAccount])
        case .waiting, .running: break
        }
        let note = statusNote(accountID: s.accountID, status: s.status)
        switch s.test {
        case .finished(let verdict) where !verdict.passed:
            return AccountNewTestResultBlock(.failed, .critical, "xmark.octagon.fill", verdict.headline, detail: note, mono: verdict.detailLine,
                                             primary: .editAndRetry, secondary: [.keep, .saveInactive], destructive: .delete,
                                             footnote: afterNote(s.status))
        case .interrupted: return incomplete(AccountTestPresentation.interruptedText, note: note)
        case .notStarted(let message): return incomplete(message, note: note)
        default: return nil
        }
    }
    public static func buttonTitle(_ button: AccountNewTestResultBlock.Button, status: AccountNewScheduleStatus) -> String {
        switch button {
        case .viewAccount: "查看账号"
        case .done: "完成"
        case .retryEnable: "重试启用"
        case .editAndRetry: "修改凭据后重试"
        case .retest: "重新测试"
        case .keep: keepTitle(status)
        case .saveInactive: saveInactiveVerb
        case .delete: "删除账号…"
        case .repause: "重试停止调度"
        case .back: "返回表单"
        }
    }
    /// 20 §7.3: marked as an error, or reading as one, keeps 错误; otherwise a known status means paused (a pass cleared the error).
    public static func status(after verdict: AccountNewTestVerdict, readBack: String?, previous: AccountNewScheduleStatus) -> AccountNewScheduleStatus {
        let after = verdict.statusAfter ?? readBack
        if AccountNewFlow.heldInError(markedError: verdict.markedError, statusAfterTest: after) { return .error }
        return after == nil ? previous : .paused
    }
    public static func statusNote(accountID: Int, status: AccountNewScheduleStatus) -> String {
        status == .error ? "后端已把账号 #\(accountID) 标为“错误”，并停止调度，不会接收请求。" : "账号 #\(accountID) 已停止调度，不会接收请求。"
    }

    // MARK: Back on the form (20 §7.4-2, -3)

    public static func banner(accountID: Int, status: AccountNewScheduleStatus, reason: String?, incomplete: Bool,
                              retryTitle: String) -> (title: String, detail: String) {
        let lead = reason.map { $0 + "。" } ?? ""
        let tail = "，或者先保留、停用、删除。"
        if status == .error, !incomplete {
            return ("测试未通过 · #\(accountID) 已标为错误", lead + "已停止调度，不会接收请求；改好凭据后点“\(retryTitle)”" + tail)
        }
        return (incomplete ? "测试没有完成 · #\(accountID) 已创建" : "测试未通过 · #\(accountID) 已创建", lead + "已停止调度；改好后点“\(retryTitle)”" + tail)
    }
    public static func credentialNote(accountID: Int, status: AccountNewScheduleStatus) -> String {
        status == .error
            ? "账号 #\(accountID) 已创建，已被标为错误（已停止调度）；这里的修改会在“保存并重新测试”时保存到它，测试通过后错误自动清除。"
            : "账号 #\(accountID) 已创建，暂停调度中；这里的修改会在“保存并重新测试”时保存到它。"
    }
    public static func resolveDialog(name: String, accountID: Int, status: AccountNewScheduleStatus, incomplete: Bool,
                                     hasUnsavedChanges: Bool) -> AccountNewResolveDialog {
        let state = status == .error ? "后端已把账号 #\(accountID) 标为错误并停止调度" : "账号 #\(accountID) 现在暂停调度"
        let unsaved = hasUnsavedChanges ? "这里的修改还没保存到 #\(accountID)。" : ""
        return AccountNewResolveDialog(title: "账号「\(name)」已创建，怎么处理？",
                                       message: "\(incomplete ? "测试没有完成" : "测试没通过")，\(state)，不会接收请求。" + unsaved,
                                       keepTitle: keepTitle(status), cancelTitle: "继续修改")
    }
    public static func dockText(accountID: Int, status: AccountNewScheduleStatus, hasChanges: Bool) -> AccountNewTestDockText {
        hasChanges ? AccountNewTestDockText(title: "保存到账号 #\(accountID)", detail: "测试通过才启用调度")
            : AccountNewTestDockText(title: "账号 #\(accountID) · \(status.title)", detail: "没有改动，用原设置再测一次")
    }
    /// The output folded after the test: its last line and how many lines it had.
    public static func outputSummary(lines: [String], lineCount: Int) -> AccountNewTestOutputSummary? {
        guard let last = lines.last else { return nil }
        return AccountNewTestOutputSummary(last: last, count: "\(lineCount) 行")
    }

    // MARK: Receipts (20 §7.1 去向, §7.4-3, -4)

    public static func completed(name: String) -> AccountNewTestReceipt {
        AccountNewTestReceipt(text: "已创建「\(name)」· \(AccountNewScheduleStatus.active.title)", systemImage: "checkmark.circle", tone: .ok, button: .view)
    }
    public static func kept(name: String, status: AccountNewScheduleStatus) -> AccountNewTestReceipt {
        status == .error
            ? AccountNewTestReceipt(text: "已保留「\(name)」· \(status.title)", systemImage: "xmark.octagon", tone: .critical, button: .view)
            : AccountNewTestReceipt(text: "已保留「\(name)」· \(AccountNewScheduleStatus.paused.title)", systemImage: "pause.circle", tone: .neutral, button: .view)
    }
    public static func savedInactive(name: String) -> AccountNewTestReceipt {
        AccountNewTestReceipt(text: "已保存「\(name)」为停用 · 不参与调度", systemImage: "minus.circle", tone: .neutral, button: .view)
    }
    public static func actionFailed(_ verb: String, reason: String) -> AccountNewTestReceipt {
        AccountNewTestReceipt(text: "\(verb)没有成功：\(reason)", systemImage: "exclamationmark.triangle", tone: .critical, button: nil)
    }
    public static func movedToBackground(name: String) -> AccountNewTestReceipt {
        AccountNewTestReceipt(text: "「\(name)」在后台继续测试，完成后通知你", systemImage: "hourglass", tone: .neutral, button: nil)
    }
    public static func background(name: String, result: AccountNewBackgroundResult) -> AccountNewTestReceipt {
        switch result {
        case .passed:
            AccountNewTestReceipt(text: "「\(name)」测试通过 · 已启用调度", systemImage: "checkmark.circle", tone: .ok, button: .view)
        case .enableFailed:
            AccountNewTestReceipt(text: "「\(name)」测试通过 · 启用调度没有成功", systemImage: "exclamationmark.triangle", tone: .caution, button: .view)
        case .failed(let status):
            AccountNewTestReceipt(text: "「\(name)」测试未通过 · \(status == .error ? "已标为错误（已停止调度）" : "仍暂停调度")", systemImage: "xmark.octagon",
                                  tone: .critical, button: .resolve)
        case .incomplete:
            AccountNewTestReceipt(text: "「\(name)」\(AccountTestPresentation.interruptedText) · 仍暂停调度", systemImage: "exclamationmark.triangle",
                                  tone: .caution, button: .resolve)
        }
    }

    // MARK: Rows

    private static func writeRow(_ s: AccountNewTestSnapshot) -> AccountNewTestStageRow {
        let id = "#\(s.accountID)"
        guard s.isRetry else { return AccountNewTestStageRow(.create, "创建账号", .done, meta: id) }
        switch s.write {
        case .running: return AccountNewTestStageRow(.save, "保存修改", .running)
        case .done: return AccountNewTestStageRow(.save, "保存修改", .done, meta: id)
        case .unchanged: return AccountNewTestStageRow(.save, "保存修改", .off, meta: "没有改动")
        case .failed(let reason): return AccountNewTestStageRow(.save, "保存修改", .failed, detail: reason)
        }
    }
    private static func pauseRow(_ s: AccountNewTestSnapshot) -> AccountNewTestStageRow {
        let title = "停止调度"
        if s.isRetry {
            return AccountNewTestStageRow(.pause, title, .done, meta: s.isPassed ? nil : (s.status == .error ? "错误 · 不接收请求" : "保持暂停"))
        }
        switch s.pause {
        case .running: return AccountNewTestStageRow(.pause, title, .running)
        case .unconfirmed: return AccountNewTestStageRow(.pause, title, .failed, meta: "没有确认")
        case .done: return AccountNewTestStageRow(.pause, title, .done, meta: s.isPassed ? nil : "不接收请求")
        }
    }
    private static func testRow(_ s: AccountNewTestSnapshot) -> AccountNewTestStageRow {
        let title = "测试连接", model = s.model ?? AccountTestPresentation.defaultModelLabel
        switch s.test {
        case .waiting: return AccountNewTestStageRow(.test, title, .waiting)
        case .preparing: return AccountNewTestStageRow(.test, title, .running)
        case .running: return AccountNewTestStageRow(.test, title, .running, meta: model)
        case .finished(let verdict):
            return AccountNewTestStageRow(.test, title, verdict.passed ? .done : .failed, meta: model, offersModelChange: !s.isBusy)
        case .interrupted, .notStarted: return AccountNewTestStageRow(.test, title, .failed, meta: model, offersModelChange: !s.isBusy)
        }
    }
    private static func enableRow(_ s: AccountNewTestSnapshot) -> AccountNewTestStageRow {
        let title = "启用调度"
        switch s.enable {
        case .running: return AccountNewTestStageRow(.enable, title, .running)
        case .done: return AccountNewTestStageRow(.enable, title, .done, meta: AccountNewScheduleStatus.active.title)
        case .failed: return AccountNewTestStageRow(.enable, title, .failed, meta: "没有成功")
        case .waiting: return s.testEndedWithoutPass ? AccountNewTestStageRow(.enable, title, .off, meta: "未启用") : AccountNewTestStageRow(.enable, title, .waiting)
        }
    }

    private static func incomplete(_ title: String, note: String) -> AccountNewTestResultBlock {
        AccountNewTestResultBlock(.incomplete, .caution, "exclamationmark.triangle.fill", title, detail: note, primary: .retest,
                                  secondary: [.keep, .saveInactive], destructive: .delete)
    }
    private static func keepTitle(_ status: AccountNewScheduleStatus) -> String { status == .error ? "保留（错误状态）" : "保留，暂停调度" }
    /// Design `an-after-note`.
    private static func afterNote(_ status: AccountNewScheduleStatus) -> String {
        let keep = status == .error ? "保留：以后在详情里改好凭据再测试，通过后错误自动清除，再启用调度。" : "保留：以后在详情里改好凭据再启用调度。"
        return keep + "停用：状态改为“停用”。点上面的模型名可以换个模型再测。"
    }
}
