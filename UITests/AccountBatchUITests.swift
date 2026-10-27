import XCTest

/// 20 §8 batch scheduling on the account list (S2-07), on the fixture site's 11 demo accounts. Anthropic holds 1, 2 and 3
/// (all scheduling); OpenAI holds 4 and the account in error, 7.
final class AccountBatchUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    private enum Fixture {
        static let site = "批量操作站点"
        static let longWindows = "-ui-accounts-long-windows"
        static let bulkPartial = "-ui-accounts-bulk-partial"
        static let bulkFail = "-ui-accounts-bulk-fail"
    }

    @MainActor func testSelectionModeHidesTabBarAndDoneRestoresIt() {
        launchAndOpenAccounts()
        defer { diagnostics("batch-select-final") }
        let select = app.buttons["accounts.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(select.label, "选择")
        select.tap()
        XCTAssertTrue(element("accounts.batch.dock").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(select.label, "完成")
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForNonExistence(timeout: 5), app.debugDescription)
        // The separate search tab (Tab(role: .search)) leaves with the bar.
        let search = app.buttons["magnifyingglass"]
        XCTAssertFalse(search.exists && search.isHittable, app.debugDescription)
        XCTAssertEqual(element("accounts.batch.count").label, "已选 0 个")
        XCTAssertFalse(app.buttons["accounts.batch.stop"].isEnabled)
        XCTAssertFalse(app.buttons["accounts.batch.enable"].isEnabled)
        diagnostics("batch-select-empty")
        let row = app.buttons["account.4"]
        reveal(row)
        row.tap()
        XCTAssertTrue(row.isSelected, app.debugDescription)
        XCTAssertFalse(app.navigationBars["OpenAI-主力-01"].exists, app.debugDescription)
        waitForLabel(element("accounts.batch.count"), equal: "已选 1 个")
        XCTAssertTrue(app.buttons["accounts.batch.stop"].isEnabled && app.buttons["accounts.batch.enable"].isEnabled)
        diagnostics("batch-select-one")
        row.tap()
        waitForLabel(element("accounts.batch.count"), equal: "已选 0 个")
        XCTAssertFalse(row.isSelected)
        select.tap()
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("accounts.batch.dock").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(select.label, "选择")
    }

    @MainActor func testSectionSelectAllAndCollapsedPickedCount() {
        launchAndOpenAccounts()
        defer { diagnostics("batch-section-final") }
        enterSelection()
        let selectAll = app.buttons["accounts.section.anthropic.selectAll"]
        reveal(selectAll)
        selectAll.tap()
        waitForLabel(element("accounts.batch.count"), equal: "已选 3 个")
        XCTAssertTrue(selectAll.label.hasSuffix("取消全选"), selectAll.label)
        // A collapsed section shows “已选 3” beside 取消全选; VoiceOver reads it in the header's label.
        let header = element("accounts.section.anthropic")
        header.tap()
        waitForLabel(header, containing: "已收起")
        XCTAssertTrue(header.label.contains("已选 3 个"), header.label)
        XCTAssertFalse(app.buttons["account.1"].exists, app.debugDescription)
        diagnostics("batch-section-collapsed")
        selectAll.tap()
        waitForLabel(element("accounts.batch.count"), equal: "已选 0 个")
        XCTAssertFalse(header.label.contains("已选"), header.label)
        XCTAssertTrue(selectAll.label.hasSuffix("全选") && !selectAll.label.hasSuffix("取消全选"), selectAll.label)
    }

    @MainActor func testStopSchedulingShowsReceiptAndUndoRestores() {
        launchAndOpenAccounts()
        defer { diagnostics("batch-stop-final") }
        enterSelection()
        let row = app.buttons["account.4"]
        reveal(row)
        row.tap()
        app.buttons["accounts.batch.stop"].tap()
        waitForReceipt("已停止调度 1 个账号")
        // The receipt stays 4.2 seconds: 撤销 first, then the rest (the paused row is checked in the partial-failure test).
        let undo = app.buttons["receipt.action"]
        XCTAssertEqual(undo.label, "撤销")
        undo.tap()
        waitForReceipt("已启用调度 1 个账号")
        XCTAssertFalse(app.buttons["receipt.action"].exists, app.debugDescription)
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(element("accounts.batch.dock").exists, app.debugDescription)
        waitForLabel(row, containing: "正常")
    }

    @MainActor func testPartialFailureOpensResultsSheet() {
        launchAndOpenAccounts(arguments: [Fixture.bulkPartial])
        defer { diagnostics("batch-partial-final") }
        enterSelection()
        let selectAll = app.buttons["accounts.section.openai.selectAll"]
        reveal(selectAll, towardBottom: false)
        selectAll.tap()
        waitForLabel(element("accounts.batch.count"), equal: "已选 2 个")
        app.buttons["accounts.batch.stop"].tap()
        waitForReceipt("已停止调度 1 个账号 · 1 个失败")
        let details = app.buttons["receipt.action"]
        XCTAssertEqual(details.label, "查看")
        details.tap()
        XCTAssertTrue(app.navigationBars["批量操作结果"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("accounts.batch.results.site").label.contains(Fixture.site), app.debugDescription)
        let failed = element("accounts.batch.result.7")
        XCTAssertTrue(failed.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(failed.label.contains("OpenAI-备用-A（#7）") && failed.label.contains("服务器拒绝"), failed.label)
        XCTAssertFalse(failed.label.contains("fixture"), failed.label)
        XCTAssertTrue(app.buttons["accounts.batch.results.undo"].exists, app.debugDescription)
        XCTAssertEqual(app.buttons["accounts.batch.results.undo"].label, "撤销已停止调度的 1 个")
        diagnostics("batch-partial-sheet")
        app.buttons["accounts.batch.results.done"].tap()
        XCTAssertTrue(app.navigationBars["批量操作结果"].waitForNonExistence(timeout: 5), app.debugDescription)
        // The batch left selection mode and read the list again: the account that went through is paused, the other unchanged.
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForExistence(timeout: 5), app.debugDescription)
        waitForLabel(app.buttons["account.4"], containing: "暂停")
        waitForLabel(app.buttons["account.7"], containing: "错误")
    }

    @MainActor func testWholeFailureKeepsSelectionAndReceiptSitsAboveDock() {
        launchAndOpenAccounts(arguments: [Fixture.bulkFail])
        defer { diagnostics("batch-fail-final") }
        enterSelection()
        let row = app.buttons["account.4"]
        reveal(row)
        row.tap()
        app.buttons["accounts.batch.stop"].tap()
        waitForReceipt("批量操作没有成功：站点暂时不可用")
        let dock = element("accounts.batch.dock")
        XCTAssertTrue(dock.exists, app.debugDescription)
        XCTAssertEqual(element("accounts.batch.count").label, "已选 1 个")
        XCTAssertFalse(app.tabBars.buttons["账号"].exists, app.debugDescription)
        let receipt = element("receipt")
        XCTAssertLessThanOrEqual(receipt.frame.maxY, dock.frame.minY, "\(receipt.frame) \(dock.frame)")
        diagnostics("batch-fail-receipt")
    }

    @MainActor func testFaceIDDenialSendsNothingAndKeepsSelection() {
        launchAndOpenAccounts(arguments: ["-ui-faceid-on", "-ui-biometric-deny"])
        defer { diagnostics("batch-faceid-final") }
        enterSelection()
        let row = app.buttons["account.4"]
        reveal(row)
        row.tap()
        app.buttons["accounts.batch.stop"].tap()
        XCTAssertFalse(app.staticTexts["receipt.text"].waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertTrue(element("accounts.batch.dock").exists, app.debugDescription)
        waitForLabel(element("accounts.batch.count"), equal: "已选 1 个")
        app.buttons["accounts.select"].tap()
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForExistence(timeout: 5), app.debugDescription)
        waitForLabel(row, containing: "正常")
    }

    /// 00 §2.6.3 / C-1: a read-only admin access token greys both buttons, with “只读令牌” once under them.
    @MainActor func testReadOnlyTokenGreysDockButtons() {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-ui-readonly-token", Fixture.longWindows]; app.launch()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter(Fixture.site, in: "login.name")
        enter("https://accounts-batch.example.invalid", in: "login.url")
        let method = element("login.method.accessToken"); reveal(method); method.tap()
        enter("sat_fixture-readonly", in: "login.key")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForExistence(timeout: 10), app.debugDescription)
        app.tabBars.buttons["账号"].tap()
        defer { diagnostics("batch-readonly-final") }
        enterSelection()
        let row = app.buttons["account.4"]
        reveal(row)
        row.tap()
        waitForLabel(element("accounts.batch.count"), equal: "已选 1 个")
        XCTAssertFalse(app.buttons["accounts.batch.stop"].isEnabled)
        XCTAssertFalse(app.buttons["accounts.batch.enable"].isEnabled)
        XCTAssertTrue(element("readonly.caption").exists, app.debugDescription)
    }

    // MARK: - Helpers

    @MainActor private func launchAndOpenAccounts(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing", Fixture.longWindows] + arguments; app.launch()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter(Fixture.site, in: "login.name")
        enter("https://accounts-batch.example.invalid", in: "login.url")
        enter("admin@example.com", in: "login.email")
        enter("fixture-password", in: "login.password")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForExistence(timeout: 10), app.debugDescription)
        app.tabBars.buttons["账号"].tap()
        XCTAssertTrue(app.buttons["account.1"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func enterSelection() {
        let select = app.buttons["accounts.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 10), app.debugDescription)
        select.tap()
        XCTAssertTrue(element("accounts.batch.dock").waitForExistence(timeout: 5), app.debugDescription)
    }
    @MainActor private func waitForReceipt(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: app.staticTexts["receipt.text"])
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, app.debugDescription, file: file, line: line)
    }
    @MainActor private func waitForLabel(_ item: XCUIElement, containing part: String, file: StaticString = #filePath, line: UInt = #line) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", part), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 10), .completed, "“\(part)” missing in “\(item.label)”", file: file, line: line)
    }
    @MainActor private func waitForLabel(_ item: XCUIElement, equal text: String, file: StaticString = #filePath, line: UInt = #line) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 10), .completed, "“\(text)” ≠ “\(item.label)”", file: file, line: line)
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func enter(_ text: String, in identifier: String) {
        let field = element(identifier); reveal(field); field.tap(); field.typeText(text)
    }
    /// Lists create rows as they scroll in; the drag stays clear of the floating tab bar or the dock.
    @MainActor private func reveal(_ item: XCUIElement, towardBottom: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<10 {
            if item.exists && item.isHittable && isAboveBottomBar(item) { item.waitUntilSettled(); return }
            let frame = app.frame
            let top = max(frame.minY + 100, app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY + 20 : frame.minY + 100)
            let bottom = (bottomBar?.frame.minY ?? frame.maxY - 80) - 20
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            let lower = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.8))
            let upper = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.2))
            (towardBottom ? lower : upper).press(forDuration: 0.05, thenDragTo: towardBottom ? upper : lower)
        }
        XCTAssertTrue(item.exists && item.isHittable, app.debugDescription, file: file, line: line)
        item.waitUntilSettled()
    }
    @MainActor private var bottomBar: XCUIElement? {
        if app.keyboards.firstMatch.exists { return app.keyboards.firstMatch }
        let dock = element("accounts.batch.dock")
        if dock.exists { return dock }
        return app.tabBars.firstMatch.exists ? app.tabBars.firstMatch : nil
    }
    @MainActor private func isAboveBottomBar(_ item: XCUIElement) -> Bool {
        guard let bar = bottomBar else { return true }
        return item.frame.maxY <= bar.frame.minY
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
