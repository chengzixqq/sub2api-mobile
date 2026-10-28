import XCTest

/// S3-08: the top-up / refund keypad sheet (30 §3.3–§3.5, R03–R05, D26, U27). Fixtures: Alice (1) $12.50, 王小明 (3) $12.40,
/// 赵磊 (6) disabled at $0; the strip starts 王小明, Studio-K, Alice. `-ui-balance-slow / -uncertain / -rejected` decide the send
/// (DemoData+Users); `-ui-pending-money` gives Alice a $12.50 refund awaiting its check.
final class BalanceKeypadUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!
    private static let pendingReceipt = "结果未确认，已记为待核对"

    @MainActor func testKeypadKeepsSevenDigitsAndTwoDecimals() {
        launchAndLogin()
        defer { diagnostics("keypad-digits-final") }
        openFromStrip(3)
        press(".")
        XCTAssertEqual(amount.label, "$0")
        XCTAssertEqual(preview.label, "输入金额")
        XCTAssertFalse(submit.isEnabled)
        press("0", "5")
        XCTAssertEqual(amount.label, "$5")
        press("delete", "1", "2", "3", "4", "5", "6", "7", "8", ".")
        XCTAssertEqual(amount.label, "$1234567")
        for _ in 0..<7 { press("delete") }
        XCTAssertEqual(amount.label, "$0")
        press("1", "2", ".", "3", "4", "5")
        XCTAssertEqual(amount.label, "$12.34")
        XCTAssertEqual(preview.label, "充值后余额 $24.74")
        XCTAssertEqual(submit.label, "充值 $12.34")
        XCTAssertTrue(submit.isEnabled)
        diagnostics("keypad-digits")
    }

    @MainActor func testRefundAboveBalanceDisablesSubmit() {
        launchAndLogin()
        defer { diagnostics("keypad-refund-over-final") }
        openFromStrip(1)
        choose("退款")
        XCTAssertEqual(app.buttons["balance.all"].label, "全部余额 $12.50")
        press("1", "3")
        XCTAssertEqual(amount.label, "\u{2212}$13")
        XCTAssertEqual(preview.label, "超过当前余额")
        XCTAssertFalse(submit.isEnabled)
        press("delete")
        XCTAssertEqual(preview.label, "退款后余额 $11.50")
        XCTAssertTrue(submit.isEnabled)
        XCTAssertEqual(submit.label, "退款 $1.00")
    }

    @MainActor func testRefundAllBalanceUsesSetZeroWording() {
        launchAndLogin()
        defer { diagnostics("keypad-all-balance-final") }
        openFromStrip(3)
        choose("退款")
        let all = app.buttons["balance.all"]
        XCTAssertEqual(all.label, "全部余额 $12.40")
        all.tap()
        XCTAssertEqual(amount.label, "\u{2212}$12.40")
        XCTAssertEqual(preview.label, "退款后余额 $0.00")
        submit.tap()
        var alert = waitForAlert("向「王小明」退款全部余额？")
        XCTAssertTrue(labelled(containing: "按服务器执行时的余额归零。", in: alert).exists, app.debugDescription)
        diagnostics("keypad-all-balance")
        alert.buttons["取消"].tap()
        // Any change of the digits ends “全部余额”: the title names the amount again.
        press("delete")
        submit.tap()
        alert = waitForAlert("向「王小明」退款 $12.40？")
        XCTAssertFalse(labelled(containing: "归零", in: alert).exists, app.debugDescription)
        alert.buttons["取消"].tap()
        all.tap()
        submit.tap()
        waitForAlert("向「王小明」退款全部余额？").buttons["退款全部余额"].tap()
        waitForReceipt("已向 王小明 退款全部余额")
        XCTAssertTrue(element("balance.mode").waitForNonExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testDisabledUserTopupWarns() {
        launchAndLogin()
        defer { diagnostics("keypad-disabled-final") }
        openUser(6, name: "赵磊")
        app.buttons["user.balance"].tap()
        XCTAssertTrue(element("balance.mode").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("balance.user").label.contains("已禁用"), element("balance.user").label)
        press("5")
        submit.tap()
        let alert = waitForAlert("向「赵磊」充值 $5.00？")
        XCTAssertTrue(labelled(containing: "充值后仍不能调用，需先启用。", in: alert).exists, app.debugDescription)
        diagnostics("keypad-disabled")
        alert.buttons["取消"].tap()
    }

    @MainActor func testFaceIDLineAboveThreshold() {
        launchAndLogin(["-ui-faceid-on"])
        defer { diagnostics("keypad-faceid-final") }
        openFromStrip(3)
        press("1", "5", "0")
        submit.tap()
        var alert = waitForAlert("向「王小明」充值 $150.00？")
        XCTAssertTrue(labelled(containing: "Face ID", in: alert).exists, app.debugDescription)
        alert.buttons["取消"].tap()
        press("delete", "delete", "delete", "5", "0")
        submit.tap()
        alert = waitForAlert("向「王小明」充值 $50.00？")
        XCTAssertFalse(labelled(containing: "Face ID", in: alert).exists, app.debugDescription)
        alert.buttons["取消"].tap()

        app.terminate()
        launchAndLogin(["-ui-faceid-on", "-ui-biometric-deny"])
        openFromStrip(3)
        press("1", "5", "0")
        submit.tap()
        waitForAlert("向「王小明」充值 $150.00？").buttons["充值 $150.00"].tap()
        // Face ID failed: nothing saved or sent, the sheet stays.
        XCTAssertTrue(submit.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["receipt.text"].exists, app.debugDescription)
        XCTAssertEqual(amount.label, "$150")
    }

    @MainActor func testTopupFromQuickStripUpdatesTheList() {
        launchAndLogin()
        defer { diagnostics("keypad-topup-final") }
        openFromStrip(1)
        press("5")
        submit.tap()
        waitForAlert("向「Alice」充值 $5.00？").buttons["充值 $5.00"].tap()
        waitForReceipt("已向 Alice 充值 $5.00")
        XCTAssertTrue(element("balance.mode").waitForNonExistence(timeout: 5), app.debugDescription)
        let row = app.buttons["user.1"]
        XCTAssertTrue(waitUntil(row, "label CONTAINS '$17.50'"), row.label)
    }

    @MainActor func testLaterKeepsTheRecordAndShowsTheBanner() {
        launchAndLogin([BalanceArgument.slow])
        defer { diagnostics("keypad-later-final") }
        openUser(1, name: "Alice")
        topUpFromDetail("5")
        let status = element("balance.status")
        XCTAssertTrue(waitUntil(status, "label CONTAINS '已等待'"), status.label)
        XCTAssertTrue(status.label.contains("正在等待服务器结果…"), status.label)
        diagnostics("keypad-later")
        app.buttons["balance.later"].tap()
        waitForReceipt(Self.pendingReceipt)
        XCTAssertTrue(element("balance.mode").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(pendingCheck.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(labelled(containing: "充值 $5.00 结果待核对").exists, app.debugDescription)
    }

    @MainActor func testUncertainTopupAsksTwiceForTheSameDirection() {
        launchAndLogin([BalanceArgument.uncertain])
        defer { diagnostics("keypad-twice-final") }
        openUser(1, name: "Alice")
        topUpFromDetail("5")
        waitForReceipt(Self.pendingReceipt)
        XCTAssertTrue(pendingCheck.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["user.balance"].tap()
        let first = waitForAlert("上一笔 $5.00 充值结果未确认")
        XCTAssertTrue(labelled(containing: "先核对可避免重复入账", in: first).exists, app.debugDescription)
        for title in ["先核对", "仍要充值", "取消"] { XCTAssertTrue(first.buttons[title].exists, title + "\n" + app.debugDescription) }
        first.buttons["仍要充值"].tap()
        XCTAssertTrue(element("balance.mode").waitForExistence(timeout: 10), app.debugDescription)
        press("2", "0")
        submit.tap()
        let second = waitForAlert("向「Alice」充值 $20.00？")
        XCTAssertTrue(labelled(containing: "上一笔 $5.00 充值还没核对。如果它其实已入账，这一笔会再入账一次。", in: second).exists, app.debugDescription)
        XCTAssertTrue(second.buttons["仍要充值 $20.00"].exists, app.debugDescription)
        diagnostics("keypad-twice")
        second.buttons["取消"].tap()
        app.buttons["sheet.close"].tap()
        XCTAssertTrue(element("balance.mode").waitForNonExistence(timeout: 5), app.debugDescription)
        // The other direction is not held back.
        app.buttons["user.refund"].tap()
        XCTAssertTrue(element("balance.mode").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
    }

    @MainActor func testPendingRefundFixtureAsksBeforeRefund() {
        launchAndLogin(["-ui-pending-money"])
        defer { diagnostics("keypad-pending-refund-final") }
        openUser(1, name: "Alice")
        app.buttons["user.refund"].tap()
        waitForAlert("上一笔 $12.50 退款结果未确认").buttons["取消"].tap()
        XCTAssertFalse(element("balance.mode").exists, app.debugDescription)
        app.buttons["user.balance"].tap()
        XCTAssertTrue(element("balance.mode").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
    }

    @MainActor func testRejectedAmountStaysInSheet() {
        launchAndLogin([BalanceArgument.rejected])
        defer { diagnostics("keypad-rejected-final") }
        openFromStrip(1)
        press("5")
        submit.tap()
        waitForAlert("向「Alice」充值 $5.00？").buttons["充值 $5.00"].tap()
        let notice = element("balance.notice")
        XCTAssertTrue(notice.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(notice.label.contains("金额不合法，未入账"), notice.label)
        XCTAssertTrue(element("balance.mode").exists && submit.isEnabled, app.debugDescription)
        app.buttons["sheet.close"].tap()
        // Refused before it ran: nothing is kept to be checked.
        XCTAssertEqual(app.buttons["users.quick.1"].label, "给Alice充值，余额 $12.50")
    }

    @MainActor func testReconcileFirstRunsTheCheck() {
        launchAndLogin([BalanceArgument.uncertain, "-ui-reconcile-executed"])
        defer { diagnostics("keypad-reconcile-first-final") }
        openUser(1, name: "Alice")
        topUpFromDetail("5")
        waitForReceipt(Self.pendingReceipt)
        XCTAssertTrue(pendingCheck.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["user.balance"].tap()
        waitForAlert("上一笔 $5.00 充值结果未确认").buttons["先核对"].tap()
        let receipt = app.staticTexts["receipt.text"]
        XCTAssertTrue(waitUntil(receipt, "label BEGINSWITH '已核对'"), receipt.label)
        XCTAssertTrue(pendingCheck.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("balance.mode").exists, app.debugDescription)
    }
}

private enum BalanceArgument {
    static let slow = "-ui-balance-slow"
    static let uncertain = "-ui-balance-uncertain"
    static let rejected = "-ui-balance-rejected"
}

extension BalanceKeypadUITests {
    @MainActor private var amount: XCUIElement { app.staticTexts["balance.amount"] }
    @MainActor private var preview: XCUIElement { app.staticTexts["balance.preview"] }
    @MainActor private var submit: XCUIElement { app.buttons["balance.submit"] }
    /// The detail's banner: its “核对” button carries the record's id.
    @MainActor private var pendingCheck: XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'user.pending.check.'")).firstMatch
    }

    @MainActor private func launchAndLogin(_ arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10), app.debugDescription)
        enter("https://keypad.example.invalid", in: app.textFields["login.url"])
        enter("键盘验收", in: app.textFields["login.name"])
        enter("admin@example.com", in: app.textFields["login.email"])
        enter("fixture-password", in: app.secureTextFields["login.password"])
        if app.keyboards.firstMatch.exists {
            app.typeText("\n")
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        }
        tap(submit)
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription)
    }
    /// The user tab → the strip's avatar → the top-up keypad.
    @MainActor private func openFromStrip(_ id: Int) {
        app.tabBars.buttons["用户"].tap()
        let avatar = app.buttons["users.quick.\(id)"]
        XCTAssertTrue(avatar.waitForExistence(timeout: 10), app.debugDescription)
        for _ in 0..<4 where !avatar.isHittable { element("users.quick").swipeLeft() }
        avatar.waitUntilSettled()
        avatar.tap()
        XCTAssertTrue(element("balance.mode").waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func openUser(_ id: Int, name: String) {
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10), app.debugDescription)
        let row = app.buttons["user.\(id)"]
        app.scrollUntilExists(row)
        row.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["user.balance"].waitForExistence(timeout: 10), app.debugDescription)
    }
    /// 充值 on the detail, the amount, the confirmation accepted.
    @MainActor private func topUpFromDetail(_ digits: String) {
        app.buttons["user.balance"].tap()
        XCTAssertTrue(element("balance.mode").waitForExistence(timeout: 10), app.debugDescription)
        press(digits.map { String($0) })
        submit.tap()
        let title = "充值 $" + digits + ".00"
        waitForAlert("向「Alice」\(title)？").buttons[title].tap()
    }
    @MainActor private func choose(_ mode: String) {
        element("balance.mode").buttons[mode].tap()
        XCTAssertTrue(waitUntil(submit, "label BEGINSWITH %@", mode), submit.label)
    }
    @MainActor private func press(_ keys: String...) { press(keys) }
    @MainActor private func press(_ keys: [String]) {
        for key in keys { app.buttons["balance.key." + (key == "." ? "dot" : key)].tap() }
    }
    @MainActor @discardableResult
    private func waitForAlert(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let alert = app.alerts[title]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), title + "\n" + app.debugDescription, file: file, line: line)
        return alert
    }
    @MainActor private func waitForReceipt(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let receipt = app.staticTexts["receipt.text"]
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: receipt)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, "\(receipt.label) ≠ \(text)\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor private func waitUntil(_ item: XCUIElement, _ format: String, _ arguments: any CVarArg...) -> Bool {
        let predicate = NSPredicate(format: format, argumentArray: arguments)
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: item)], timeout: 10) == .completed
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func labelled(containing text: String, in root: XCUIElement? = nil) -> XCUIElement {
        (root ?? app).descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
    @MainActor private func tap(_ item: XCUIElement) { reveal(item); item.tap() }
    @MainActor private func enter(_ value: String, in field: XCUIElement) { tap(field); field.typeText(value) }
    /// The login form: drags above the keyboard until the field can be tapped.
    @MainActor private func reveal(_ item: XCUIElement) {
        for _ in 0..<8 where !(item.exists && item.isHittable) {
            let frame = app.frame, keyboard = app.keyboards.firstMatch, bar = app.navigationBars.firstMatch
            let top = max(frame.minY + 100, bar.exists ? bar.frame.maxY + 20 : frame.minY + 100)
            let bottom = min(frame.maxY - 100, keyboard.exists ? keyboard.frame.minY - 20 : frame.maxY - 100)
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            let lower = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.85))
            let upper = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.25))
            let down = !(item.exists && item.frame.maxY < top)
            (down ? lower : upper).press(forDuration: 0.05, thenDragTo: down ? upper : lower)
        }
        XCTAssertTrue(item.exists && item.isHittable, app.debugDescription)
    }
    @MainActor private func diagnostics(_ name: String) {
        guard let app, app.state != .notRunning else { return }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
