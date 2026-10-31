import Foundation
import Testing
@testable import Sub2Core

// 20 §7.3 测试 sheet and §7.4-1…-4 (S2-20): the four progress rows, the result blocks, the banner, the note above the
// credentials, the question 处理 asks, the dock after a failed test and every receipt.

private typealias Snapshot = AccountNewTestSnapshot
private typealias Presentation = AccountNewTestPresentation

private let failedVerdict = AccountNewTestVerdict(passed: false, markedError: true, statusAfter: "error", reason: "API Key 无效或已撤销",
                                                  detailLine: "上游返回 401 · invalid x-api-key")
private let passedVerdict = AccountNewTestVerdict(passed: true, statusAfter: "active", clearedError: true, timing: "首字 1.2s · 总耗时 3.4s")

private func row(_ snapshot: Snapshot, _ index: Int) -> AccountNewTestStageRow { Presentation.rows(snapshot)[index] }

@Test func rowsWhilePausingAndAfterCreateWithSchedulingOff() {
    let pausing = Snapshot(accountID: 13, pause: .running)
    #expect(Presentation.rows(pausing).map(\.title) == ["创建账号", "停止调度", "测试连接", "启用调度"])
    #expect(row(pausing, 0).state == .done && row(pausing, 0).meta == "#13")
    #expect(row(pausing, 1).state == .running && row(pausing, 2).state == .waiting && row(pausing, 3).state == .waiting)
    let unconfirmed = Snapshot(accountID: 13, pause: .unconfirmed)
    #expect(row(unconfirmed, 1).state == .failed && row(unconfirmed, 1).meta == "没有确认")

    let testing = Snapshot(accountID: 13, test: .running, model: "claude-sonnet-4-5")
    #expect(row(testing, 1).state == .done && row(testing, 1).meta == "不接收请求")
    #expect(row(testing, 2).state == .running && row(testing, 2).meta == "claude-sonnet-4-5" && !row(testing, 2).offersModelChange)
    #expect(row(testing, 3).state == .waiting)
    #expect(row(Snapshot(accountID: 13, test: .running), 2).meta == "默认模型")
    let preparing = Snapshot(accountID: 13, test: .preparing)
    #expect(row(preparing, 2).state == .running && row(preparing, 2).meta == nil)
}

@Test func rowsWhenPassedFailedOrEnabling() {
    let passed = Snapshot(accountID: 13, test: .finished(passedVerdict), enable: .done, model: "m")
    // Scheduling is on once passed: a test with another model could fail without the backend turning it off.
    #expect(row(passed, 2).state == .done && !row(passed, 2).offersModelChange)
    #expect(row(passed, 3).state == .done && row(passed, 3).meta == "参与调度")
    #expect(row(passed, 1).meta == nil)

    let failed = Snapshot(accountID: 13, test: .finished(failedVerdict), model: "m", status: .error)
    #expect(row(failed, 2).state == .failed && row(failed, 2).offersModelChange)
    #expect(row(failed, 3).state == .off && row(failed, 3).meta == "未启用")
    #expect(row(failed, 1).meta == "不接收请求")

    let enabling = Snapshot(accountID: 13, test: .finished(passedVerdict), enable: .running)
    #expect(row(enabling, 3).state == .running && !row(enabling, 2).offersModelChange)
    let enableFailed = Snapshot(accountID: 13, test: .finished(passedVerdict), enable: .failed("网络连接失败"))
    #expect(row(enableFailed, 3).state == .failed && row(enableFailed, 3).meta == "没有成功")
    #expect(!row(enableFailed, 2).offersModelChange)
    for test in [Snapshot.Test.interrupted, .notStarted("测试没有开始")] {
        #expect(row(Snapshot(accountID: 13, test: test), 3).state == .off)
        #expect(row(Snapshot(accountID: 13, test: test), 2).state == .failed)
    }
}

@Test func rowsOnRetry() {
    let saving = Snapshot(accountID: 13, isRetry: true, write: .running)
    #expect(row(saving, 0).title == "保存修改" && row(saving, 0).stage == .save && row(saving, 0).state == .running)
    #expect(row(Snapshot(accountID: 13, isRetry: true, write: .done), 0).meta == "#13")
    let unchanged = row(Snapshot(accountID: 13, isRetry: true, write: .unchanged), 0)
    #expect(unchanged.state == .off && unchanged.meta == "没有改动")
    let refused = row(Snapshot(accountID: 13, isRetry: true, write: .failed("账号已被其他人修改")), 0)
    #expect(refused.state == .failed && refused.detail == "账号已被其他人修改")
    #expect(row(Snapshot(accountID: 13, isRetry: true, status: .paused), 1).meta == "保持暂停")
    #expect(row(Snapshot(accountID: 13, isRetry: true, status: .error), 1).meta == "错误 · 不接收请求")
    #expect(row(Snapshot(accountID: 13, isRetry: true, test: .finished(passedVerdict), enable: .done, status: .error), 1).meta == nil)
    #expect(row(Snapshot(accountID: 13, isRetry: true, pause: .unconfirmed), 1).state == .done)
}

@Test func passedAndEnableFailedBlocks() throws {
    let passed = try #require(Presentation.resultBlock(Snapshot(accountID: 13, test: .finished(passedVerdict), enable: .done)))
    #expect(passed.kind == .passed && passed.title == "测试通过 · 已启用调度" && passed.tone == .ok)
    #expect(passed.detail == "错误状态已自动清除。首字 1.2s · 总耗时 3.4s")
    #expect(passed.primary == .done && passed.secondary == [.viewAccount] && passed.destructive == nil)
    let local = AccountNewTestVerdict(passed: true, timing: "首字 1.2s · 总耗时 3.4s · 本机计时")
    #expect(Presentation.resultBlock(Snapshot(accountID: 13, test: .finished(local), enable: .done))?.detail == "首字 1.2s · 总耗时 3.4s · 本机计时")
    #expect(Presentation.resultBlock(Snapshot(accountID: 13, test: .finished(AccountNewTestVerdict(passed: true)), enable: .done))?.detail == nil)

    let failed = try #require(Presentation.resultBlock(Snapshot(accountID: 13, test: .finished(passedVerdict), enable: .failed("网络连接失败"))))
    #expect(failed.kind == .enableFailed && failed.title == "测试通过 · 启用调度没有成功" && failed.detail == "网络连接失败")
    #expect(failed.primary == .retryEnable && failed.secondary == [.viewAccount] && failed.tone == .caution)
    #expect(Presentation.resultBlock(Snapshot(accountID: 13, test: .finished(passedVerdict), enable: .running)) == nil)
    #expect(Presentation.resultBlock(Snapshot(accountID: 13, test: .running)) == nil)
}

@Test func failedBlocksFollowTheHeldStatus() throws {
    let error = try #require(Presentation.resultBlock(Snapshot(accountID: 13, test: .finished(failedVerdict), status: .error)))
    #expect(error.kind == .failed && error.title == "测试未通过 · API Key 无效或已撤销" && error.mono == "上游返回 401 · invalid x-api-key")
    #expect(error.detail == "后端已把账号 #13 标为“错误”，并停止调度，不会接收请求。" && error.tone == .critical)
    #expect(error.primary == .editAndRetry && error.secondary == [.keep, .saveInactive] && error.destructive == .delete)
    #expect(error.footnote?.hasPrefix("保留：以后在详情里改好凭据再测试，通过后错误自动清除") == true)
    #expect(Presentation.buttonTitle(.keep, status: .error) == "保留（错误状态）")
    #expect(Presentation.buttonTitle(.keep, status: .paused) == "保留，暂停调度")
    #expect(Presentation.buttonTitle(.delete, status: .paused) == "删除账号…")
    #expect(Presentation.buttonTitle(.editAndRetry, status: .paused) == "修改凭据后重试")

    let quiet = AccountNewTestVerdict(passed: false)
    let paused = try #require(Presentation.resultBlock(Snapshot(accountID: 13, test: .finished(quiet), status: .paused)))
    #expect(paused.title == "测试未通过" && paused.mono == nil && paused.detail == "账号 #13 已停止调度，不会接收请求。")
    #expect(paused.footnote?.hasPrefix("保留：以后在详情里改好凭据再启用调度。") == true)
}

@Test func pauseUnconfirmedIncompleteAndSaveFailureBlocks() throws {
    let pause = try #require(Presentation.resultBlock(Snapshot(accountID: 13, pause: .unconfirmed)))
    #expect(pause.kind == .pauseUnconfirmed && pause.title == "停止调度没有确认 · 结果待核对" && pause.tone == .critical)
    #expect(pause.detail == "账号 #13 已创建，可能正在参与调度。凭据还没验证，可能已经在接收请求。重试一次停止调度，成功后自动开始测试。")
    #expect(pause.primary == .repause && pause.secondary.isEmpty && pause.destructive == .delete)

    let interrupted = try #require(Presentation.resultBlock(Snapshot(accountID: 13, test: .interrupted)))
    #expect(interrupted.kind == .incomplete && interrupted.title == "测试被中断，不能判定是否成功")
    #expect(interrupted.primary == .retest && interrupted.secondary == [.keep, .saveInactive] && interrupted.destructive == .delete)
    #expect(interrupted.detail == "账号 #13 已停止调度，不会接收请求。")
    #expect(Presentation.resultBlock(Snapshot(accountID: 13, test: .notStarted("测试没有开始：网络连接失败")))?.title == "测试没有开始：网络连接失败")

    let save = try #require(Presentation.resultBlock(Snapshot(accountID: 13, isRetry: true, write: .failed("没有保存成功"))))
    #expect(save.kind == .writeFailed && save.title == "修改没有保存到账号 #13" && save.primary == .back && save.destructive == nil)
    #expect(Presentation.buttonTitle(.back, status: .paused) == "返回表单")
}

@Test func statusAfterTheTest() {
    #expect(Presentation.status(after: failedVerdict, readBack: nil, previous: .paused) == .error)
    #expect(Presentation.status(after: AccountNewTestVerdict(passed: false), readBack: "error", previous: .paused) == .error)
    #expect(Presentation.status(after: AccountNewTestVerdict(passed: false), readBack: nil, previous: .error) == .error)
    #expect(Presentation.status(after: AccountNewTestVerdict(passed: false), readBack: nil, previous: .paused) == .paused)
    #expect(Presentation.status(after: AccountNewTestVerdict(passed: false, statusAfter: "active"), readBack: nil, previous: .error) == .paused)
    #expect(Presentation.status(after: passedVerdict, readBack: "error", previous: .error) == .paused)
}

@Test func sheetTitleFollowsTheRetry() {
    #expect(Presentation.sheetTitle(Snapshot(accountID: 13)) == "创建并测试")
    #expect(Presentation.sheetTitle(Snapshot(accountID: 13, isRetry: true, write: .running)) == "保存并重新测试")
    #expect(Presentation.sheetTitle(Snapshot(accountID: 13, isRetry: true, write: .unchanged)) == "重新测试")
}

@Test func bannerAndCredentialNote() {
    let error = Presentation.banner(accountID: 13, status: .error, reason: "API Key 无效或已撤销", incomplete: false, retryTitle: "保存并重新测试")
    #expect(error.title == "测试未通过 · #13 已标为错误")
    #expect(error.detail == "API Key 无效或已撤销。已停止调度，不会接收请求；改好凭据后点“保存并重新测试”，或者先保留、停用、删除。")
    let paused = Presentation.banner(accountID: 13, status: .paused, reason: nil, incomplete: false, retryTitle: "重新测试")
    #expect(paused.title == "测试未通过 · #13 已创建" && paused.detail == "已停止调度；改好后点“重新测试”，或者先保留、停用、删除。")
    let incomplete = Presentation.banner(accountID: 13, status: .paused, reason: nil, incomplete: true, retryTitle: "重新测试")
    #expect(incomplete.title == "测试没有完成 · #13 已创建")

    #expect(Presentation.credentialNote(accountID: 13, status: .paused) == "账号 #13 已创建，暂停调度中；这里的修改会在“保存并重新测试”时保存到它。")
    #expect(Presentation.credentialNote(accountID: 13, status: .error)
            == "账号 #13 已创建，已被标为错误（已停止调度）；这里的修改会在“保存并重新测试”时保存到它，测试通过后错误自动清除。")
}

@Test func resolveQuestionAndDockText() {
    let error = Presentation.resolveDialog(name: "Claude-04", accountID: 13, status: .error, incomplete: false, hasUnsavedChanges: false)
    #expect(error.title == "账号「Claude-04」已创建，怎么处理？")
    #expect(error.message == "测试没通过，后端已把账号 #13 标为错误并停止调度，不会接收请求。")
    #expect(error.keepTitle == "保留（错误状态）" && error.cancelTitle == "继续修改")
    let paused = Presentation.resolveDialog(name: "Claude-04", accountID: 13, status: .paused, incomplete: false, hasUnsavedChanges: true)
    #expect(paused.message == "测试没通过，账号 #13 现在暂停调度，不会接收请求。这里的修改还没保存到 #13。")
    #expect(paused.keepTitle == "保留，暂停调度")
    let incomplete = Presentation.resolveDialog(name: "Claude-04", accountID: 13, status: .paused, incomplete: true, hasUnsavedChanges: false)
    #expect(incomplete.message == "测试没有完成，账号 #13 现在暂停调度，不会接收请求。")

    #expect(Presentation.dockText(accountID: 13, status: .paused, hasChanges: true) == AccountNewTestDockText(title: "保存到账号 #13", detail: "测试通过才启用调度"))
    #expect(Presentation.dockText(accountID: 13, status: .paused, hasChanges: false)
            == AccountNewTestDockText(title: "账号 #13 · 暂停调度", detail: "没有改动，用原设置再测一次"))
    #expect(Presentation.dockText(accountID: 13, status: .error, hasChanges: false).title == "账号 #13 · 错误（已停止调度）")
}

@Test func receiptsTable() {
    let rows: [(AccountNewTestReceipt, String, Tone, AccountNewTestReceipt.Button?)] = [
        (Presentation.completed(name: "A"), "已创建「A」· 参与调度", .ok, .view),
        (Presentation.kept(name: "A", status: .error), "已保留「A」· 错误（已停止调度）", .critical, .view),
        (Presentation.kept(name: "A", status: .paused), "已保留「A」· 暂停调度", .neutral, .view),
        (Presentation.savedInactive(name: "A"), "已保存「A」为停用 · 不参与调度", .neutral, .view),
        (Presentation.actionFailed("保存为停用", reason: "站点暂时不可用"), "保存为停用没有成功：站点暂时不可用", .critical, nil),
        (Presentation.movedToBackground(name: "A"), "「A」在后台继续测试，完成后通知你", .neutral, nil),
        (Presentation.background(name: "A", result: .passed), "「A」测试通过 · 已启用调度", .ok, .view),
        (Presentation.background(name: "A", result: .enableFailed), "「A」测试通过 · 启用调度没有成功", .caution, .view),
        (Presentation.background(name: "A", result: .failed(.error)), "「A」测试未通过 · 已标为错误（已停止调度）", .critical, .resolve),
        (Presentation.background(name: "A", result: .failed(.paused)), "「A」测试未通过 · 仍暂停调度", .critical, .resolve),
        (Presentation.background(name: "A", result: .incomplete), "「A」测试被中断，不能判定是否成功 · 仍暂停调度", .caution, .resolve)
    ]
    for (receipt, text, tone, button) in rows {
        #expect(receipt.text == text && receipt.tone == tone && receipt.button == button, "\(text)")
    }
    #expect(Presentation.movedToBackground(name: "A").systemImage == "hourglass")
    #expect(AccountNewTestReceipt.Button.view.title == "查看" && AccountNewTestReceipt.Button.resolve.title == "处理")
}

@Test func outputSummaryFoldsToTheLastLine() {
    #expect(Presentation.outputSummary(lines: [], lineCount: 0) == nil)
    #expect(Presentation.outputSummary(lines: ["a", "b"], lineCount: 37) == AccountNewTestOutputSummary(last: "b", count: "37 行"))
}

@Test func snapshotFlags() {
    #expect(Snapshot(accountID: 13, isRetry: true, write: .running).isBusy)
    #expect(Snapshot(accountID: 13, pause: .running).isBusy)
    #expect(Snapshot(accountID: 13, test: .preparing).isBusy && !Snapshot(accountID: 13, test: .preparing).allowsBackground)
    #expect(Snapshot(accountID: 13, test: .running).isBusy && Snapshot(accountID: 13, test: .running).allowsBackground)
    #expect(Snapshot(accountID: 13, test: .finished(passedVerdict), enable: .running).isBusy)
    #expect(!Snapshot(accountID: 13, test: .finished(failedVerdict)).isBusy)
    #expect(Snapshot(accountID: 13, enable: .done).isPassed && !Snapshot(accountID: 13, enable: .failed(nil)).isPassed)
}

@Test func verdictFromS213Outcome() {
    let failure = AccountTestOutcome(result: AccountTestResult(success: false, totalMs: 820, upstreamStatus: 401,
                                                               account: .init(status: "error", schedulable: false, errorKind: "auth"),
                                                               marked: .init(error: true, rateLimited: false, tempUnschedulable: false)),
                                     errorText: "invalid x-api-key")
    let key = AccountNewTestVerdict(outcome: failure, credential: .apiKey)
    #expect(!key.passed && key.markedError && key.statusAfter == "error" && key.reason == "API Key 无效或已撤销")
    #expect(key.headline == "测试未通过 · API Key 无效或已撤销" && key.detailLine == "上游返回 401 · invalid x-api-key")
    #expect(AccountNewTestVerdict(outcome: failure, credential: .token).reason == "令牌无效或已撤销")

    let pass = AccountTestOutcome(result: AccountTestResult(success: true, firstTokenMs: 1210, totalMs: 3420,
                                                            recovery: .init(clearedError: true, clearedRateLimit: false)), errorText: nil)
    let passed = AccountNewTestVerdict(outcome: pass, credential: .apiKey)
    #expect(passed.passed && passed.clearedError && passed.reason == nil && passed.detailLine == nil)
    #expect(passed.timing == "首字 1.2s · 总耗时 3.4s")
    let legacy = AccountTestOutcome.legacy(passed: true, timing: AccountTestTiming(firstTokenMs: nil, totalMs: 2000, isLocal: true),
                                           before: .init(status: "active", schedulable: false), after: .init(status: "active", schedulable: false),
                                           now: Date(timeIntervalSince1970: 0), errorText: nil)
    let local = AccountNewTestVerdict(outcome: legacy, credential: .apiKey)
    #expect(local.timing?.hasSuffix("本机计时") == true && local.statusAfter == "active")
}
