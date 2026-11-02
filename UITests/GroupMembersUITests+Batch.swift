import XCTest

/// 50 §5 逐项结果 (S5-09) on `-ui-group-batch-partial` (S5D2a-12): Claude Code 组 (5) adding Claude-官方-03 (3) alone fails
/// MIXED_CHANNEL_RISK; Codex 专线 (11) adding OpenAI-主力-01 (4) and OpenAI-备用-A (7) gets 7 ACCOUNT_NOT_FOUND and 4 in.
/// `-ui-group-batch-retry-offline` loses the page's own retries and undos.
extension GroupMembersUITests {
    enum BatchFixture {
        static let retryOffline = "-ui-group-batch-retry-offline"
    }
    static let mixedChannelMessage = "分组里已有 Antigravity 账号。同一分组混用 Anthropic 与 Antigravity 账号可能导致思考块签名校验失败，历史消息会降级为非思考模式。"

    /// Confirm, 重试后已加入, 全部完成, then 撤销 to 已全部撤销; the account is not a member afterwards.
    @MainActor func testBatchResultRetriesMixedChannelAfterConfirmThenUndoesAll() {
        openBatchResults(group: 5, picks: [3], submit: "加入 1 个账号", receipt: "加入失败 · 1 个账号没有改动", subtitle: "Claude Code 组 · 1 个账号")
        defer { diagnostics("group-batch-retry-undo-final") }
        XCTAssertEqual(element("group.batch.card.failed").label, "1 个失败")
        XCTAssertFalse(element("group.batch.card.succeeded").exists, app.debugDescription)
        XCTAssertEqual(element("group.batch.card.note").label, "失败的账号没有改动，可以直接重试，或点开账号单独处理。")
        XCTAssertEqual(element("group.batch.section.failed").value as? String, "1 个 · 没有改动")
        expectBatchRow(3, contains: ["Claude-官方-03", "加入失败", "分组里已有 Antigravity 账号，与 Anthropic 账号混用有风险"])
        let retry = app.buttons["group.batch.retry"], undo = app.buttons["group.batch.undo"]
        XCTAssertEqual(retry.label, "重试 1 个")
        XCTAssertFalse(undo.exists, app.debugDescription)

        retry.tap()
        let alert = mixedChannelAlert()
        alert.buttons["仍然加入"].firstMatch.tap()
        waitForReceipt("重试成功 · 已加入 1 个账号")
        XCTAssertTrue(element("group.batch.section.failed").pollGone(timeout: 5), app.debugDescription)
        expectBatchRow(3, contains: ["Claude-官方-03", "重试后已加入"])
        XCTAssertEqual(element("group.batch.card.quiet").label, "全部完成 · 已加入 1 个账号")
        XCTAssertFalse(retry.exists, app.debugDescription)
        XCTAssertTrue(undo.poll(NSPredicate(format: "label == %@", "撤销成功的 1 个"), timeout: 5), app.debugDescription)

        undo.tap()
        waitForReceipt("已撤销 1 个账号的改动")
        expectBatchRow(3, contains: ["已撤销"])
        XCTAssertTrue(element("group.batch.card.quiet").poll(NSPredicate(format: "label == %@", "已全部撤销"), timeout: 5), app.debugDescription)
        XCTAssertTrue(undo.pollGone(timeout: 5), app.debugDescription)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("group.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        app.scrollUntilExists(member(1))
        XCTAssertTrue(member(3).pollGone(timeout: 10), app.debugDescription)
    }

    /// ACCOUNT_NOT_FOUND cannot be retried; undoing the added one leaves the failure; a row opens its account and back keeps the page.
    @MainActor func testBatchResultListsNotFoundAndUndoesTheAddedAccount() {
        openBatchResults(group: 11, picks: [4, 7], submit: "加入 2 个账号", receipt: "已加入 1 个，1 个失败", subtitle: "Codex 专线 · 2 个账号")
        defer { diagnostics("group-batch-not-found-final") }
        XCTAssertEqual(element("group.batch.card.failed").label, "1 个失败")
        XCTAssertEqual(element("group.batch.card.succeeded").label, "1 个成功")
        expectBatchRow(7, contains: ["OpenAI-备用-A", "加入失败", "账号不存在或已删除"])
        XCTAssertFalse(app.buttons["group.batch.retry"].exists, app.debugDescription)
        XCTAssertEqual(element("group.batch.section.succeeded").value as? String, "1 个")
        expectBatchRow(4, contains: ["OpenAI-主力-01", "已加入"])
        let undo = app.buttons["group.batch.undo"]
        XCTAssertEqual(undo.label, "撤销成功的 1 个")

        undo.tap()
        waitForReceipt("已撤销 1 个账号的改动")
        expectBatchRow(4, contains: ["已撤销"])
        XCTAssertEqual(element("group.batch.card.failed").label, "1 个失败")
        XCTAssertFalse(element("group.batch.card.succeeded").exists, app.debugDescription)
        XCTAssertFalse(element("group.batch.card.quiet").exists, app.debugDescription)
        XCTAssertTrue(undo.pollGone(timeout: 5), app.debugDescription)

        batchRow(4).tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(batchRow(4).waitForExistence(timeout: 10), app.debugDescription)
        expectBatchRow(4, contains: ["已撤销"])
    }

    /// 取消 sends nothing; a retry lost on the way says 没有完成，请稍后重试 and the row stays failed.
    @MainActor func testBatchResultRequestFailureShowsLineAndKeepsRows() {
        openBatchResults(group: 5, picks: [3], submit: "加入 1 个账号", receipt: "加入失败 · 1 个账号没有改动", subtitle: "Claude Code 组 · 1 个账号",
                         arguments: [BatchFixture.retryOffline])
        defer { diagnostics("group-batch-offline-final") }
        let retry = app.buttons["group.batch.retry"]
        retry.tap()
        let alert = mixedChannelAlert()
        alert.buttons["取消"].firstMatch.tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5), app.debugDescription)
        expectBatchRow(3, contains: ["加入失败"])
        XCTAssertFalse(element("group.batch.requestFailure").exists, app.debugDescription)

        retry.tap()
        mixedChannelAlert().buttons["仍然加入"].firstMatch.tap()
        let line = element("group.batch.requestFailure")
        XCTAssertTrue(line.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(line.label, "没有完成，请稍后重试")
        expectBatchRow(3, contains: ["加入失败", "分组里已有 Antigravity 账号，与 Anthropic 账号混用有风险"])
        XCTAssertEqual(element("group.batch.card.failed").label, "1 个失败")
        XCTAssertFalse(app.staticTexts["receipt.text"].exists, app.debugDescription)
        XCTAssertTrue(retry.poll(NSPredicate(format: "isEnabled == true"), timeout: 5), app.debugDescription)
    }

    // MARK: - Helpers

    /// The group's 添加账号 from its button row, the picks, then the receipt's 查看 onto the page.
    @MainActor func openBatchResults(group: Int, picks: [Int], submit: String, receipt: String, subtitle: String, arguments: [String] = [],
                                     file: StaticString = #filePath, line: UInt = #line) {
        openGroup(group, arguments: [Fixture.batchPartial] + arguments)
        app.buttons["group.action.addAccounts"].tap()
        XCTAssertTrue(pickRow(picks[0]).waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        picks.forEach { pickRow($0).tap() }
        submitPicks(titled: submit, file: file, line: line)
        waitForReceipt(receipt, file: file, line: line)
        tapReceiptAction(titled: "查看", file: file, line: line)
        let title = app.navigationBars["逐项结果"]
        XCTAssertTrue(title.waitForExistence(timeout: 10) || app.navigationBars.staticTexts["逐项结果"].exists, app.debugDescription, file: file, line: line)
        let shown = app.navigationBars.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", subtitle)).firstMatch
        XCTAssertTrue(shown.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
    }
    @MainActor func batchRow(_ id: Int) -> XCUIElement { element("group.batch.row.\(id)") }
    @MainActor func expectBatchRow(_ id: Int, contains parts: [String], file: StaticString = #filePath, line: UInt = #line) {
        let row = batchRow(id)
        let predicate = NSPredicate(format: parts.map { _ in "label CONTAINS %@" }.joined(separator: " AND "), argumentArray: parts)
        XCTAssertTrue(row.poll(predicate, timeout: 5), "\(parts) not in “\(row.exists ? row.label : "-")”\n\(app.debugDescription)", file: file, line: line)
    }
    /// 5.4's confirmation, with its message.
    @MainActor func mixedChannelAlert(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let alert = app.alerts["仍然加入混合渠道账号？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription, file: file, line: line)
        XCTAssertTrue(alert.staticTexts[Self.mixedChannelMessage].exists, app.debugDescription, file: file, line: line)
        return alert
    }
}
