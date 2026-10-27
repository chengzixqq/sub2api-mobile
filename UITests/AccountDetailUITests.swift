import XCTest

/// 20 §2 account detail top half (S2-08) on the fixture site's demo accounts (DemoData+Accounts). Most tests add
/// -ui-accounts-long-windows so the timed windows and model limits hold through a slow run.
final class AccountDetailUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    private enum Fixture {
        static let site = "账号详情站点"
        static let longWindows = "-ui-accounts-long-windows"
        static let detailError = "-ui-account-detail-error"
        static let removed = "-ui-account-removed"
        static let groupTransition = "-ui-account-group-transition"
        static let errorSummary = "401 凭据已失效（invalid_api_key）"
    }

    /// Claude-官方-03 is rate limited with two model limits; its switch is on.
    @MainActor func testRateLimitedAccountShowsCountdownResumeTimeAndModelLimits() {
        openDetail(3)
        defer { diagnostics("account-detail-limited-final") }
        XCTAssertEqual(element("account.detail.card.title").label, "限流中")
        XCTAssertEqual(element("account.detail.card.cause").label, "上游 429")
        let countdown = element("account.detail.countdown")
        XCTAssertTrue(countdown.exists, app.debugDescription)
        XCTAssertNotNil(countdown.label.range(of: #"^\d+:\d{2}(:\d{2})?$"#, options: .regularExpression), countdown.label)
        let resume = element("account.detail.resume-note").label
        XCTAssertNotNil(resume.range(of: #"^后自动恢复 · 预计 \d{2}:\d{2}$"#, options: .regularExpression), resume)
        XCTAssertEqual(element("account.detail.model-limits.title").label, "模型限流 2")
        for model in ["claude-opus-4", "claude-sonnet-4-5"] {
            let row = element("account.detail.model-limit.\(model)")
            XCTAssertTrue(row.exists, app.debugDescription)
            XCTAssertTrue(row.label.contains(model) && row.label.hasSuffix("后"), row.label)
        }
        let recover = app.buttons["account.action.recover"], test = app.buttons["account.action.test"], stop = app.buttons["account.action.stop"]
        for button in [recover, test, stop] { XCTAssertTrue(button.exists && button.isHittable, app.debugDescription) }
        XCTAssertLessThan(recover.frame.minX, test.frame.minX)
        XCTAssertLessThan(test.frame.minX, stop.frame.minX)
        diagnostics("account-detail-limited")
    }

    /// OpenAI-备用-A has an auth error and was stopped when it failed: the fix leads, then 恢复状态 and 测试连接.
    @MainActor func testCredentialErrorAccountLeadsWithReplaceKey() {
        openDetail(7)
        defer { diagnostics("account-detail-credential-final") }
        XCTAssertEqual(element("account.detail.card.title").label, "错误")
        XCTAssertEqual(element("account.detail.error-body").label, Fixture.errorSummary)
        XCTAssertTrue(element("account.detail.schedule-note").label.contains("出错时已自动停止调度"), app.debugDescription)
        let fix = app.buttons["account.action.replaceKey"], recover = app.buttons["account.action.recover"], test = app.buttons["account.action.test"]
        for button in [fix, recover, test] { XCTAssertTrue(button.exists, app.debugDescription) }
        XCTAssertEqual(fix.label, "更换 API Key…")
        XCTAssertLessThan(fix.frame.minX, recover.frame.minX)
        XCTAssertLessThan(recover.frame.minX, test.frame.minX)
        XCTAssertFalse(app.buttons["account.action.stop"].exists || app.buttons["account.action.resume"].exists, app.debugDescription)
        diagnostics("account-detail-credential")
        fix.tap()
        XCTAssertTrue(element("route.placeholder").waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["sheet.close"].tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 5), app.debugDescription)
    }

    /// Gemini-测试-B has its switch off: 启用调度 leads, its receipt offers 撤销, and 撤销 pauses it again.
    @MainActor func testPausedAccountEnableSchedulingReceiptAndUndo() {
        openDetail(5)
        defer { diagnostics("account-detail-resume-final") }
        let title = element("account.detail.card.title")
        XCTAssertEqual(title.label, "暂停 · 不参与调度")
        app.buttons["account.action.resume"].tap()
        waitForReceipt("已启用调度")
        XCTAssertTrue(app.buttons["account.action.stop"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("account.detail.card.title").label, "正常 · 参与调度")
        app.buttons.matching(NSPredicate(format: "identifier == 'receipt.action' AND label == '撤销'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["account.action.resume"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(element("account.detail.card.title").label, "暂停 · 不参与调度")
    }

    /// 20 §5.3: an account stopped by its error may recover with or without scheduling.
    @MainActor func testRecoverDialogOffersBothChoicesWhenSchedulingIsOff() {
        openDetail(7)
        defer { diagnostics("account-detail-recover-two-final") }
        app.buttons["account.action.recover"].tap()
        XCTAssertTrue(dialogButton("恢复并启用调度").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(dialogButton("只恢复状态（保持暂停）").exists, app.debugDescription)
        diagnostics("account-detail-recover-two")
        dismissDialog()
        XCTAssertTrue(dialogButton("恢复并启用调度").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("account.detail.card.title").label, "错误")
        XCTAssertFalse(app.staticTexts["receipt.text"].exists, app.debugDescription)
    }

    @MainActor func testRecoverDialogSingleChoiceWhenSchedulingIsOn() {
        openDetail(3)
        defer { diagnostics("account-detail-recover-one-final") }
        app.buttons["account.action.recover"].tap()
        XCTAssertTrue(dialogButton("恢复状态").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(dialogButton("恢复并启用调度").exists, app.debugDescription)
        dismissDialog()
        XCTAssertTrue(app.buttons["account.action.recover"].waitForExistence(timeout: 5), app.debugDescription)
    }

    /// 20 §2.5: a failed GET :id keeps the list's snapshot on screen under the banner.
    @MainActor func testSnapshotBannerWhenDetailReadFails() {
        openDetail(1, arguments: [Fixture.detailError])
        defer { diagnostics("account-detail-snapshot-final") }
        XCTAssertTrue(element("account.detail.snapshot-banner").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text("读取最新数据失败，显示的是列表里的快照").exists, app.debugDescription)
        XCTAssertTrue(app.buttons["account.action.test"].exists, app.debugDescription)
        XCTAssertTrue(app.navigationBars["Claude-官方-01"].exists, app.debugDescription)
        diagnostics("account-detail-snapshot")
        app.buttons["account.detail.snapshot-banner.retry"].tap()
        XCTAssertTrue(element("account.detail.snapshot-banner").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("account.detail.card").exists, app.debugDescription)
    }

    /// 404 ACCOUNT_NOT_FOUND: the whole page says so.
    @MainActor func testRemovedAccountReplacesWholePage() {
        launchAndOpenAccounts(arguments: [Fixture.removed])
        let row = app.buttons["account.1"]
        reveal(row)
        row.tap()
        defer { diagnostics("account-detail-removed-final") }
        let removed = element("account.detail.removed")
        XCTAssertTrue(removed.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(removed.label, "这个账号已删除。")
        XCTAssertFalse(element("account.detail.card").exists, app.debugDescription)
        XCTAssertFalse(app.buttons["account.detail.more"].exists, app.debugDescription)
    }

    /// AccountDestination(id:) (the request detail's “查看账号”) opens the new page with only the id.
    @MainActor func testDetailOpenedFromRequestLogUsesNewScreen() {
        openAccountFromRequestLog()
        defer { diagnostics("account-detail-from-log-final") }
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Claude-官方-01"].exists, app.debugDescription)
    }

    @MainActor func testDetailOpenedByIDShowsFailurePageWhenReadFails() {
        openAccountFromRequestLog(arguments: [Fixture.detailError])
        defer { diagnostics("account-detail-by-id-failure-final") }
        XCTAssertTrue(element("account.detail.failure").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(text("读取账号失败").exists, app.debugDescription)
        XCTAssertTrue(app.buttons["account.detail.retry"].isHittable, app.debugDescription)
        XCTAssertFalse(element("account.detail.card").exists, app.debugDescription)
    }

    /// ⋯ keeps the old edit page for every account and the old token refresh for token accounts until S2-10 / S2-16.
    @MainActor func testMoreMenuKeepsTransitionalItems() {
        openDetail(4)
        defer { diagnostics("account-detail-more-final") }
        app.buttons["account.detail.more"].tap()
        XCTAssertTrue(menuButton("编辑账号").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(menuButton("刷新令牌").exists, app.debugDescription)
        menuButton("编辑账号").tap()
        XCTAssertTrue(element("account.edit.name").waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["取消"].tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 5), app.debugDescription)
        goBack()
        let row = app.buttons["account.1"]
        reveal(row, towardBottom: false)
        row.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["account.detail.more"].tap()
        XCTAssertTrue(menuButton("刷新令牌").waitForExistence(timeout: 5), app.debugDescription)
        menuButton("刷新令牌").tap()
        XCTAssertTrue(dialogButton("刷新令牌").waitForExistence(timeout: 5), app.debugDescription)
        dismissDialog()
        XCTAssertTrue(dialogButton("刷新令牌").waitForNonExistence(timeout: 5), app.debugDescription)
    }

    /// S2D1-18: the group page's transitional account list pushes the detail itself, and going back stays in that list.
    @MainActor func testGroupTransitionRowOpensDetailAndBackReturnsToGroupAccounts() {
        launchAndLogin(arguments: [Fixture.groupTransition])
        defer { diagnostics("account-detail-group-transition-final") }
        app.openSearchItem("search.item.groups")
        let group = app.buttons["group.10"]
        XCTAssertTrue(group.waitForExistence(timeout: 10), app.debugDescription)
        group.tap()
        let entry = app.buttons["group.accounts"]
        app.scrollUntilExists(entry)
        entry.tap()
        let row = app.buttons["account.4"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        row.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["OpenAI-主力-01"].exists, app.debugDescription)
        goBack()
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("account.detail.card").exists, app.debugDescription)
    }

    // MARK: - Helpers

    @MainActor private func launchAndLogin(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing", Fixture.longWindows] + arguments; app.launch()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter(Fixture.site, in: "login.name")
        enter("https://account-detail.example.invalid", in: "login.url")
        enter("admin@example.com", in: "login.email")
        enter("fixture-password", in: "login.password")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func launchAndOpenAccounts(arguments: [String] = []) {
        launchAndLogin(arguments: arguments)
        app.tabBars.buttons["账号"].tap()
        XCTAssertTrue(element("accounts.chip.all").waitForExistence(timeout: 10), app.debugDescription)
    }
    /// The list's row, so the page opens on its snapshot; waits for the server's copy unless the read fails.
    @MainActor private func openDetail(_ id: Int, arguments: [String] = []) {
        launchAndOpenAccounts(arguments: arguments)
        let row = app.buttons["account.\(id)"]
        reveal(row)
        row.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func openAccountFromRequestLog(arguments: [String] = []) {
        launchAndLogin(arguments: arguments)
        app.openSearchItem("search.item.usage")
        let request = app.buttons["logs.request.101"]
        XCTAssertTrue(request.waitForExistence(timeout: 10), app.debugDescription)
        request.tap()
        let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '查看账号'")).firstMatch
        app.scrollUntilExists(link)
        link.tap()
    }
    @MainActor private func waitForReceipt(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: app.staticTexts["receipt.text"])
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, app.debugDescription, file: file, line: line)
    }
    /// Dialog buttons, apart from the page's own button of the same title.
    @MainActor private func dialogButton(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH 'account.action.')", label)).firstMatch
    }
    /// The dialog's 取消 where the system draws one; otherwise a tap beside the floating dialog closes it.
    @MainActor private func dismissDialog() {
        let cancel = dialogButton("取消")
        if cancel.waitForExistence(timeout: 2) { cancel.tap(); return }
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.exists, app.debugDescription)
        let below = sheet.frame.maxY + 80
        let y = below < app.frame.maxY - 120 ? below : sheet.frame.minY - 80
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: sheet.frame.midX, dy: y)).tap()
    }
    /// System menu items are found by their title.
    @MainActor private func menuButton(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
    @MainActor private func text(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
    @MainActor private func goBack() { app.navigationBars.buttons.element(boundBy: 0).tap() }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func enter(_ text: String, in identifier: String) {
        let field = element(identifier); reveal(field); field.tap(); field.typeText(text)
    }
    /// Lists create rows as they scroll in; the drag stops before the floating tab bar, and the list settles before a tap.
    @MainActor private func reveal(_ item: XCUIElement, towardBottom: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<10 {
            if item.exists && item.isHittable && isAboveTabBar(item) { item.waitUntilSettled(); return }
            let frame = app.frame
            let top = max(frame.minY + 100, app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY + 20 : frame.minY + 100)
            let bottom = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 20
                : app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 20 : frame.maxY - 100
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            let lower = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.8))
            let upper = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.2))
            (towardBottom ? lower : upper).press(forDuration: 0.05, thenDragTo: towardBottom ? upper : lower)
        }
        XCTAssertTrue(item.exists && item.isHittable, app.debugDescription, file: file, line: line)
        item.waitUntilSettled()
    }
    @MainActor private func isAboveTabBar(_ item: XCUIElement) -> Bool {
        let bar = app.tabBars.firstMatch
        return !bar.exists || item.frame.maxY <= bar.frame.minY
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
