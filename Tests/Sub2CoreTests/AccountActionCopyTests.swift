import Foundation
import Testing
@testable import Sub2Core

/// 2027-01-15T08:00:00Z, the site clock every case reads.
private let copyNow = Date(timeIntervalSince1970: 1_800_000_000)

private func stamp(_ seconds: TimeInterval) -> String { ServerTime.utcTimestamp(copyNow.addingTimeInterval(seconds)) }
private func limits(_ offsets: [TimeInterval]) -> AccountExtra {
    AccountExtra(modelRateLimitEntries: Dictionary(uniqueKeysWithValues: offsets.enumerated().map {
        ("model-\($0.offset)", AccountExtra.ModelRateLimitEntry(rateLimitResetAt: stamp($0.element)))
    }))
}
private func copyAccount(name: String = "账号", status: String = "active", schedulable: Bool = true, rateLimit: TimeInterval? = nil,
                         overload: TimeInterval? = nil, temporary: TimeInterval? = nil, models: [TimeInterval] = [],
                         autoPause: Bool? = nil, expires: TimeInterval? = nil) -> UpstreamAccount {
    UpstreamAccount(id: 4, name: name, platform: "openai", type: "apikey", status: status, schedulable: schedulable,
                    expiresAt: expires.map { Int64(copyNow.addingTimeInterval($0).timeIntervalSince1970) },
                    extra: models.isEmpty ? nil : limits(models), rateLimitResetAt: rateLimit.map(stamp), overloadUntil: overload.map(stamp),
                    tempUnschedulableUntil: temporary.map(stamp), autoPauseOnExpired: autoPause)
}
private let pausedTail = "这个账号已停止调度，恢复后仍是暂停，除非同时启用调度。"

// MARK: - Recover dialog (20 §5.3)

@Test func recoverDialogForErrorAccountWithSwitchOff() {
    let dialog = AccountActionCopy.recoverDialog(for: copyAccount(name: "OpenAI-备用-A", status: "error", schedulable: false), now: copyNow)
    #expect(dialog.title == "恢复「OpenAI-备用-A」？")
    #expect(dialog.message == "清除错误状态。出错时账号已被停止调度，恢复后仍是暂停，除非同时启用调度。")
    #expect(dialog.options == [.recoverAndEnable, .recoverOnly])
    #expect(dialog.options.map(\.title) == ["恢复并启用调度", "只恢复状态（保持暂停）"])
    #expect(dialog.options.map(\.enablesScheduling) == [true, false])
}

@Test(arguments: [
    (copyAccount(schedulable: false, rateLimit: 600, models: [300, 900]), "清除限流和 2 项模型限流。" + pausedTail),
    (copyAccount(schedulable: false, overload: 60), "清除过载。" + pausedTail),
    (copyAccount(schedulable: false, temporary: 60), "清除临时不可调度。" + pausedTail)
])
func recoverDialogForLimitedAccountWithSwitchOff(account: UpstreamAccount, message: String) {
    let dialog = AccountActionCopy.recoverDialog(for: account, now: copyNow)
    #expect(dialog.message == message)
    #expect(dialog.options == [.recoverAndEnable, .recoverOnly])
}

@Test(arguments: [
    (copyAccount(rateLimit: 600, models: [300, 900]), "清除限流和 2 项模型限流，账号立即参与调度。"),
    (copyAccount(overload: 60), "清除过载，账号立即参与调度。"),
    (copyAccount(status: "error"), "清除错误状态，账号立即参与调度。"),
    (copyAccount(models: [300]), "清除当前阻断和 1 项模型限流，账号立即参与调度。")
])
func recoverDialogWithSwitchOn(account: UpstreamAccount, message: String) {
    let dialog = AccountActionCopy.recoverDialog(for: account, now: copyNow)
    #expect(dialog.message == message)
    #expect(dialog.options == [.recover])
    #expect(dialog.options.map(\.title) == ["恢复状态"])
    #expect(dialog.options.map(\.enablesScheduling) == [false])
}

@Test func recoverDialogCountsOnlyActiveModelLimits() {
    let account = copyAccount(rateLimit: 600, models: [-60, 300])
    #expect(AccountActionCopy.recoverDialog(for: account, now: copyNow).message == "清除限流和 1 项模型限流，账号立即参与调度。")
    let expired = copyAccount(rateLimit: 600, models: [-60, -30])
    #expect(AccountActionCopy.recoverDialog(for: expired, now: copyNow).message == "清除限流，账号立即参与调度。")
    // The site clock decides: an hour later both windows have passed.
    #expect(AccountActionCopy.recoverDialog(for: account, now: copyNow.addingTimeInterval(3_600)).message == "清除当前阻断，账号立即参与调度。")
}

// MARK: - Receipts (20 §5.3, §5.5)

@Test func receiptTableMatchesSpec() {
    #expect(AccountActionCopy.recovered(schedulable: true)
            == AccountReceiptCopy(text: "已恢复 · 参与调度", systemImage: "checkmark.circle", tone: .ok, button: nil))
    #expect(AccountActionCopy.recovered(schedulable: false)
            == AccountReceiptCopy(text: "已恢复 · 仍暂停调度", systemImage: "pause.fill", tone: .neutral, button: .enableScheduling))
    #expect(AccountActionCopy.scheduled(enabled: false) == AccountReceiptCopy(text: "已停止调度", systemImage: "pause.fill", tone: .neutral, button: .undo))
    #expect(AccountActionCopy.scheduled(enabled: true) == AccountReceiptCopy(text: "已启用调度", systemImage: "play.fill", tone: .ok, button: .undo))
    #expect(AccountActionCopy.accountEnabled(name: "Grok-旧-01")
            == AccountReceiptCopy(text: "已启用账号「Grok-旧-01」", systemImage: "play.fill", tone: .ok, button: .undo))
    #expect(AccountActionCopy.accountEnabled(name: "Grok-旧-01", canUndo: false).button == nil)
    #expect(AccountReceiptButton.undo.title == "撤销" && AccountReceiptButton.enableScheduling.title == "启用调度" && AccountReceiptButton.retry.title == "重试")
}

private let newKeyConflict = KeyedWriteFailure(disposition: .needsNewKey(.keyConflict), key: "k", actionID: nil, lastError: nil)

@Test(arguments: [
    (AccountActionKind.setSchedulable(false), APIError.server(status: 500, reason: nil) as any Error, "停止调度没有成功：站点暂时不可用"),
    (.setSchedulable(true), APIError.server(status: 404, reason: "ACCOUNT_NOT_FOUND"), "启用调度没有成功：这个账号已删除或不在本工作区"),
    (.recover, APIError.server(status: 403, reason: "ACCESS_TOKEN_READ_ONLY"), "恢复状态没有成功：当前管理访问令牌只读，不能执行此操作"),
    (.enableAccount, APIError.server(status: 412, reason: "ACCOUNT_VERSION_CONFLICT"), "启用账号没有成功：账号已被其他人修改"),
    (.enableAccount, APIError.server(status: 400, reason: "INVALID_IF_MATCH"), "启用账号没有成功：服务器拒绝了这次修改（INVALID_IF_MATCH）"),
    (.enableAccount, APIError.server(status: 400, reason: "INVALID_PATCH"), "启用账号没有成功：服务器拒绝了这次修改（INVALID_PATCH）"),
    (.enableAccount, APIError.server(status: 400, reason: "CREDENTIAL_KEY_NOT_DELETABLE"), "启用账号没有成功：服务器拒绝了这次修改（CREDENTIAL_KEY_NOT_DELETABLE）"),
    (.undo, newKeyConflict, "撤销没有成功：" + (newKeyConflict.errorDescription ?? ""))
])
func failureTextNamesActionAndReason(kind: AccountActionKind, error: any Error, text: String) {
    let receipt = AccountActionCopy.failed(kind, error: error)
    #expect(receipt.text == text)
    #expect(receipt.button == nil && receipt.tone == .critical)
}

@Test func resultUnknownCopies() {
    let notApplied = AccountActionCopy.notApplied(.setSchedulable(false))
    #expect(notApplied.text == "停止调度没有生效，可以重试" && notApplied.button == .retry)
    let sameKey = AccountActionCopy.unconfirmedRetry(.setSchedulable(true))
    #expect(sameKey.text == "启用调度结果未确认，可用同一编号重试" && sameKey.button == .retry)
    #expect(AccountActionCopy.unconfirmedReceipt.text == "结果未确认，请刷新核对后再操作" && AccountActionCopy.unconfirmedReceipt.button == nil)
    let cleared = APIError.server(status: 423, reason: "COMPLIANCE_REQUIRED").withSecurityOutcome(.passed)
    let reconfirm = AccountActionCopy.reconfirm(cleared)
    #expect(reconfirm.text == "合规确认已完成，请重新确认后发送" && reconfirm.button == .retry)
    #expect(AccountActionCopy.readOnly.text == "当前管理访问令牌只读，不能执行此操作" && AccountActionCopy.readOnly.button == nil)
}

// MARK: - Disposition

private let unconfirmedCauses: [KeyedWriteFailure.UnconfirmedCause] = [.transport, .stillProcessing, .storeUnavailable, .unreadableResponse]

@Test(arguments: [
    (CancellationError() as any Error, AccountWriteDisposition.cancelled),
    (APIError.server(status: 423, reason: nil).withSecurityOutcome(.cancelled), .cancelled),
    (APIError.server(status: 423, reason: nil).withSecurityOutcome(.passed), .reconfirm),
    (APIError.server(status: 403, reason: "STEP_UP_REQUIRED").withSecurityOutcome(.blocked), .failed),
    (KeyedWriteFailure(disposition: .needsNewKey(.invalid), key: "k", actionID: nil, lastError: nil), .failed),
    (APIError(kind: .transport, message: "无法连接站点"), .readBack),
    (APIError.invalidResponse, .readBack),
    (APIError.refreshDeferred, .failed),
    (APIError.server(status: 502, reason: nil), .readBack),
    (APIError.server(status: 504, reason: nil), .readBack),
    (APIError.server(status: 503, reason: nil), .readBack),
    (APIError.server(status: 503, reason: "STEP_UP_UNAVAILABLE"), .failed),
    (APIError.server(status: 500, reason: "ACCOUNT_RECOVERED_SCHEDULABLE_FAILED"), .readBack),
    (APIError.server(status: 500, reason: nil), .failed),
    (APIError.server(status: 404, reason: "ACCOUNT_NOT_FOUND"), .missing),
    (APIError.server(status: 412, reason: "ACCOUNT_VERSION_CONFLICT"), .versionConflict),
    (APIError.server(status: 400, reason: "INVALID_IF_MATCH"), .failed),
    (URLError(.badURL), .failed)
])
func dispositionClassifiesEveryErrorKind(error: any Error, expected: AccountWriteDisposition) {
    #expect(AccountActionCopy.disposition(of: error) == expected)
}

@Test(arguments: unconfirmedCauses)
func keyedUnconfirmedReadsBack(cause: KeyedWriteFailure.UnconfirmedCause) {
    let failure = KeyedWriteFailure(disposition: .unconfirmed(cause, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil)
    #expect(AccountActionCopy.disposition(of: failure) == .readBack)
}

// MARK: - Row swipe (20 §1.4, S2D1-20)

@Test(arguments: [
    (copyAccount(), AccountScheduleSwipe?.some(.stop)),
    (copyAccount(rateLimit: 600), .stop),
    (copyAccount(overload: 60), .stop),
    (copyAccount(temporary: 60), .stop),
    (copyAccount(schedulable: false), .enable),
    (copyAccount(status: "error", schedulable: false), .enable),
    (copyAccount(schedulable: false, rateLimit: 600), .enable),
    (copyAccount(status: "inactive", schedulable: false), .enable),
    (copyAccount(status: "inactive"), nil),
    (copyAccount(status: "error"), nil),
    (copyAccount(autoPause: true, expires: -60), nil),
    (copyAccount(schedulable: false, autoPause: true, expires: -60), nil),
    (copyAccount(autoPause: true, expires: 3_600), .stop)
])
func swipeActionFollowsSwitchAndState(account: UpstreamAccount, expected: AccountScheduleSwipe?) {
    #expect(AccountActionCopy.swipeAction(for: account, now: copyNow) == expected)
}

@Test func swipeTitlesAndSymbols() {
    #expect(AccountScheduleSwipe.stop.title == "停止调度" && AccountScheduleSwipe.stop.systemImage == "pause.fill" && !AccountScheduleSwipe.stop.enables)
    #expect(AccountScheduleSwipe.enable.title == "启用调度" && AccountScheduleSwipe.enable.systemImage == "play.fill" && AccountScheduleSwipe.enable.enables)
}

// MARK: - Undo and verbs

@Test func undoStatusRestoresInactiveOnly() {
    #expect(AccountActionCopy.undoStatus(from: "inactive") == .inactive)
    #expect(AccountActionCopy.undoStatus(from: "disabled") == .inactive)
    #expect(AccountActionCopy.undoStatus(from: "something-new") == .inactive)
    #expect(AccountActionCopy.undoStatus(from: "active") == nil)
    #expect(AccountActionCopy.undoStatus(from: "error") == nil)
}

@Test func kindVerbs() {
    #expect(AccountActionKind.recover.verb == "恢复状态")
    #expect(AccountActionKind.setSchedulable(true).verb == "启用调度")
    #expect(AccountActionKind.setSchedulable(false).verb == "停止调度")
    #expect(AccountActionKind.enableAccount.verb == "启用账号")
    #expect(AccountActionKind.undo.verb == "撤销")
}
