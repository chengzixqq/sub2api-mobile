import XCTest

/// 20 §4 测试连接 (S2-14) on the fixture site's demo accounts: the stream and test-runs are replayed by DemoData+AccountTests.
/// Claude-官方-01 (#1) is a healthy Anthropic OAuth account; OpenAI-备用-A (#7) is in a credential error with scheduling stopped.
final class AccountTestUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    private enum Fixture {
        static let site = "测试连接站点"
        static let fail = "-ui-account-test-fail"
        static let interrupt = "-ui-account-test-interrupt"
        static let slow = "-ui-account-test-slow"
        static let modelsError = "-ui-account-models-error"
    }

    /// 20 §4.3 / §4.4: the test starts as the sheet opens; the header names the account and the default model.
    @MainActor func testOpeningRunsTheTestAtOnce() {
        openTest(1)
        defer { diagnostics("account-test-open-final") }
        XCTAssertTrue(app.buttons["sheet.close"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["account.test.start"].exists)
        XCTAssertEqual(element("account.test.target").label, "Claude-官方-01")
        XCTAssertEqual(element("account.test.notice").label, "测试会向上游发送一次真实请求，可能产生少量费用")
        waitFor("account.test.result.title", beginsWith: "测试通过 · ")
        let output = element("account.test.output").label
        XCTAssertTrue(output.hasPrefix("→ 测试 ") && output.contains(" · Claude-官方-01"), output)
        XCTAssertTrue(output.contains("→ 模型 claude-sonnet-4-5") && output.contains("你好，连接正常。"), output)
        XCTAssertEqual(element("account.test.result.usage").label, "输入 12 · 输出 128 tokens")
        XCTAssertFalse(app.buttons["account.test.enable"].exists)
        diagnostics("account-test-open")
    }

    /// 20 §4.3 恢复说明 and §5: the pass cleared the error but the switch stays off; “启用调度” closes the sheet and the detail follows.
    @MainActor func testPassClearsErrorAndEnableSchedulingClosesSheet() {
        openTest(7)
        defer { diagnostics("account-test-enable-final") }
        waitFor("account.test.result.detail", equals: "已自动清除错误，仍暂停调度")
        let enable = app.buttons["account.test.enable"]
        XCTAssertTrue(enable.exists, app.debugDescription)
        enable.tap()
        XCTAssertTrue(element("account.test.sheet").waitForNonExistence(timeout: 10), app.debugDescription)
        waitFor("receipt.text", equals: "已启用调度")
        waitFor("account.detail.card.title", equals: "正常 · 参与调度")
    }

    /// 20 §4.3 失败结果: a key account is told to replace its key; the output keeps the upstream's error line.
    @MainActor func testCredentialFailureExplainsNextStep() {
        openTest(7, arguments: [Fixture.fail])
        defer { diagnostics("account-test-fail-final") }
        waitFor("account.test.result.title", beginsWith: "测试未通过 · 401")
        XCTAssertEqual(element("account.test.result.detail").label, "凭据无效，账号保持错误。更换 API Key 后再测试连接")
        XCTAssertFalse(app.buttons["account.test.enable"].exists)
        XCTAssertTrue(element("account.test.output").label.contains("✕ API returned 401"), element("account.test.output").label)
        app.buttons["sheet.close"].tap()
        waitFor("account.detail.card.title", equals: "错误")
    }

    /// 20 §4.4: closing does not cancel; the test ends in a receipt whose “查看” opens the account.
    @MainActor func testClosingWhileRunningLeavesTestAndReceiptOpensAccount() {
        openTest(1, arguments: [Fixture.slow])
        defer { diagnostics("account-test-close-final") }
        XCTAssertTrue(element("account.test.running").waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["sheet.close"].tap()
        XCTAssertTrue(element("account.test.sheet").waitForNonExistence(timeout: 10), app.debugDescription)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("accounts.chip.all").waitForExistence(timeout: 10), app.debugDescription)
        waitFor("receipt.text", equals: "「Claude-官方-01」测试通过", timeout: 20)
        let view = app.buttons.matching(NSPredicate(format: "identifier == 'receipt.action' AND label == '查看'")).firstMatch
        XCTAssertTrue(view.exists, app.debugDescription)
        view.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["account.action.test"].exists, app.debugDescription)
    }

    /// 20 §4.4 / §4.6: a stream cut before test_result, with an interrupted record, offers 重新测试, which polls a test run.
    @MainActor func testInterruptedTestRetestsThroughTestRuns() {
        openTest(1, arguments: [Fixture.interrupt])
        defer { diagnostics("account-test-interrupt-final") }
        waitFor("account.test.result.title", equals: "测试被中断，不能判定是否成功")
        let retry = app.buttons["account.test.retry"]
        XCTAssertTrue(retry.exists, app.debugDescription)
        retry.tap()
        XCTAssertTrue(element("account.test.running").waitForExistence(timeout: 5), app.debugDescription)
        waitFor("account.test.result.title", beginsWith: "测试通过 · ", timeout: 20)
        XCTAssertTrue(element("account.test.output").label.contains("你好，连接正常。"), element("account.test.output").label)
    }

    /// S2D1-01: without a model list the request names no model, and the server's default is used.
    @MainActor func testModelListFailureUsesServerDefaultModel() {
        openTest(1, arguments: [Fixture.modelsError])
        defer { diagnostics("account-test-default-model-final") }
        waitFor("account.test.result.title", beginsWith: "测试通过 · ")
        XCTAssertTrue(element("account.test.output").label.contains("→ 模型 默认模型"), element("account.test.output").label)
    }

    // MARK: - Helpers

    @MainActor private func openTest(_ id: Int, arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing"] + arguments; app.launchQuietly()
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter(Fixture.site, in: "login.name")
        enter("https://account-test.example.invalid", in: "login.url")
        enter("admin@example.com", in: "login.email")
        enter("fixture-password", in: "login.password")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["账号"].waitForExistence(timeout: 10), app.debugDescription)
        app.tabBars.buttons["账号"].tap()
        let row = app.buttons["account.\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        reveal(row)
        row.tap()
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 10), app.debugDescription)
        let test = app.buttons["account.action.test"]
        reveal(test)
        test.tap()
        XCTAssertTrue(element("account.test.sheet").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["测试连接"].exists, app.debugDescription)
    }
    /// The element with this identifier and label, so a row that is replaced while the test runs is matched when it is back.
    @MainActor private func waitFor(_ identifier: String, equals label: String, timeout: TimeInterval = 15,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let match = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label == %@", identifier, label)).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: timeout), app.debugDescription, file: file, line: line)
    }
    @MainActor private func waitFor(_ identifier: String, beginsWith prefix: String, timeout: TimeInterval = 15,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let match = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", identifier, prefix)).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: timeout), app.debugDescription, file: file, line: line)
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func enter(_ text: String, in identifier: String) {
        let field = element(identifier); reveal(field); field.tap(); field.typeText(text)
    }
    /// Lists create rows as they scroll in; the drag stops before the floating tab bar, and the list settles before a tap.
    @MainActor private func reveal(_ item: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<10 {
            if item.exists && item.isHittable && isAboveTabBar(item) { item.waitUntilSettled(); return }
            let frame = app.frame
            let top = max(frame.minY + 100, app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY + 20 : frame.minY + 100)
            let bottom = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 20
                : app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 20 : frame.maxY - 100
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.8))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.2)))
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
