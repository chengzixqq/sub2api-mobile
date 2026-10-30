import XCTest

/// S3-07: the user detail's pending banner (30 §2.3, R02, C-26), the check's dialogs (30 §3.4) and the foreground check
/// (30 §3.6). Fixtures: `-ui-pending-money` gives Alice a $12.50 refund (0A…01, five minutes old, S0-15); `-ui-pending-old-site`
/// an older login at the same address with Alice's $50.00 top-up (0B…01, ten minutes old); `-ui-pending-compensation-here` a
/// $10.00 compensation of Alice (0C…01); `-ui-reconcile-*` decides what the check finds (DemoData+Users). Alice's balance is $12.50.
final class BalanceReconcileUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!
    private static let refund = "0A000000-0000-4000-8000-000000000001"
    private static let oldTopUp = "0B000000-0000-4000-8000-000000000001"
    private static let grantHere = "0C000000-0000-4000-8000-000000000001"
    private static let refundChecked = "已核对：服务器已扣除 $12.50（余额 $25.00 → $12.50）"

    @MainActor func testBannerShowsEarliestOldLoginRecordFirst() {
        launchAndLogin(["-ui-pending-money", "-ui-pending-old-site"])
        defer { diagnostics("reconcile-banner-final") }
        openAlice()
        XCTAssertTrue(element("user.pending.\(Self.oldTopUp)").waitForExistence(timeout: 10), app.debugDescription)
        for text in ["充值 $50.00 结果待核对", "分钟前发起，未收到服务器确认", "这笔在本站点的旧登录下发起"] {
            XCTAssertTrue(labelled(containing: text).exists, text + "\n" + app.debugDescription)
        }
        XCTAssertTrue(app.buttons["user.pending.check.\(Self.oldTopUp)"].isHittable)
        // One balance record at a time: the refund waits for the earlier top-up.
        XCTAssertFalse(element("user.pending.\(Self.refund)").exists, app.debugDescription)
        diagnostics("reconcile-banner")
    }

    @MainActor func testExactMatchClearsBannerAndListMarks() {
        launchAndLogin(["-ui-pending-money", "-ui-reconcile-executed"])
        defer { diagnostics("reconcile-executed-final") }
        openAlice()
        check(Self.refund)
        waitForReceipt(Self.refundChecked)
        XCTAssertTrue(element("user.pending.\(Self.refund)").waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let alice = app.buttons["user.1"]
        XCTAssertTrue(alice.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitUntil(alice, "NOT (label CONTAINS '待核对')"), alice.label)
    }

    @MainActor func testNotFoundOffersRetryAbandonAndCancel() {
        launchAndLogin(["-ui-pending-money", "-ui-reconcile-notfound"])
        defer { diagnostics("reconcile-notfound-final") }
        openAlice()
        let alert = checkAndWaitForAlert(Self.refund, title: "服务器上没有这笔记录")
        XCTAssertTrue(labelled(containing: "用同一编号重试是安全的", in: alert).exists, app.debugDescription)
        for title in ["用同一编号重试", "放弃这笔", "取消"] { XCTAssertTrue(alert.buttons[title].exists, title + "\n" + app.debugDescription) }
        diagnostics("reconcile-notfound")
        alert.buttons["取消"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        XCTAssertTrue(element("user.pending.\(Self.refund)").exists, app.debugDescription)
    }

    @MainActor func testAbandonConfirmsTwiceThenShowsNextRecord() {
        launchAndLogin(["-ui-pending-money", "-ui-pending-old-site", "-ui-reconcile-notfound"])
        defer { diagnostics("reconcile-abandon-final") }
        openAlice()
        checkAndWaitForAlert(Self.oldTopUp, title: "服务器上没有这笔记录").buttons["放弃这笔"].tap()
        let confirm = app.alerts["放弃这笔？"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(labelled(containing: "余额以服务器为准", in: confirm).exists, app.debugDescription)
        XCTAssertTrue(element("user.pending.\(Self.oldTopUp)").exists)
        confirm.buttons["放弃这笔"].tap()
        XCTAssertTrue(element("user.pending.\(Self.oldTopUp)").waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("user.pending.\(Self.refund)").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(labelled(containing: "退款 $12.50 结果待核对").exists, app.debugDescription)
    }

    @MainActor func testRetrySameNumberSettlesTheRecord() {
        launchAndLogin(["-ui-pending-money", "-ui-reconcile-notfound"])
        defer { diagnostics("reconcile-retry-final") }
        openAlice()
        checkAndWaitForAlert(Self.refund, title: "服务器上没有这笔记录").buttons["用同一编号重试"].tap()
        waitForReceipt("已向 Alice 退款 $12.50")
        XCTAssertTrue(element("user.pending.\(Self.refund)").waitForNonExistence(timeout: 10), app.debugDescription)
        // The detail reads the user again after the write.
        XCTAssertTrue(waitUntil(element("user.hero.balance"), "label CONTAINS '可用余额 $0.00'"), element("user.hero.balance").label)
    }

    @MainActor func testRetryStoppedByStepUpKeepsTheRecord() {
        launchAndLogin(["-ui-pending-money", "-ui-reconcile-notfound", "-ui-step-up-required", "-ui-balance-retry-step-up"])
        defer { diagnostics("reconcile-step-up-final") }
        openAlice()
        checkAndWaitForAlert(Self.refund, title: "服务器上没有这笔记录").buttons["用同一编号重试"].tap()
        let code = element("stepup.code")
        XCTAssertTrue(code.waitForExistence(timeout: 10), app.debugDescription)
        code.tap()
        code.typeText("123456")
        XCTAssertTrue(code.waitForNonExistence(timeout: 10), app.debugDescription)
        // Verified: the same record is confirmed once more and still waits to be checked.
        let again = app.alerts["用同一编号重试？"]
        XCTAssertTrue(again.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("user.pending.\(Self.refund)").exists, app.debugDescription)
        again.buttons["用同一编号重试"].tap()
        waitForReceipt("已向 Alice 退款 $12.50")
        XCTAssertTrue(element("user.pending.\(Self.refund)").waitForNonExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testOtherAdministratorCannotRetry() {
        launchAndLogin(["-ui-pending-money", "-ui-pending-other-actor", "-ui-reconcile-notfound"])
        defer { diagnostics("reconcile-other-actor-final") }
        openAlice()
        let alert = checkAndWaitForAlert(Self.refund, title: "服务器上没有这笔记录")
        XCTAssertTrue(labelled(containing: "这笔由 bob@example.com 发起，只能由同一管理员重试；可以放弃后重新退款。", in: alert).exists, app.debugDescription)
        XCTAssertFalse(alert.buttons["用同一编号重试"].exists, app.debugDescription)
        XCTAssertTrue(alert.buttons["放弃这笔"].exists && alert.buttons["取消"].exists, app.debugDescription)
        diagnostics("reconcile-other-actor")
    }

    @MainActor func testSingleCandidateCanBeMarkedExecuted() {
        launchAndLogin(["-ui-pending-money", "-ui-reconcile-candidate"])
        defer { diagnostics("reconcile-candidate-final") }
        openAlice()
        let alert = checkAndWaitForAlert(Self.refund, title: "找到 1 条可能是这笔的记录")
        XCTAssertTrue(labelled(containing: "\u{2212}$12.50 · 余额 $25.00 → $12.50", in: alert).exists, app.debugDescription)
        for title in ["是这笔，标为已扣除", "不是，用同一编号重试", "取消"] { XCTAssertTrue(alert.buttons[title].exists, title + "\n" + app.debugDescription) }
        diagnostics("reconcile-candidate")
        alert.buttons["是这笔，标为已扣除"].tap()
        waitForReceipt(Self.refundChecked)
        XCTAssertTrue(element("user.pending.\(Self.refund)").waitForNonExistence(timeout: 10), app.debugDescription)
    }

    /// Several candidates and a fallback that could not conclude ask the same way.
    @MainActor func testAmbiguousAndInconclusivePointToWeb() {
        defer { diagnostics("reconcile-ambiguous-final") }
        for argument in ["-ui-reconcile-ambiguous", "-ui-reconcile-inconclusive"] {
            launchAndLogin(["-ui-pending-money", argument])
            openAlice()
            let alert = checkAndWaitForAlert(Self.refund, title: "无法确定这笔是否入账")
            XCTAssertTrue(labelled(containing: "余额调整记录", in: alert).exists, argument + "\n" + app.debugDescription)
            for title in ["用同一编号重试", "放弃这笔", "取消"] { XCTAssertTrue(alert.buttons[title].exists, title + "\n" + app.debugDescription) }
            alert.buttons["取消"].tap()
            XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
            XCTAssertTrue(element("user.pending.\(Self.refund)").exists, argument + "\n" + app.debugDescription)
            app.terminate()
        }
    }

    @MainActor func testStillRunningAndFailedKeepTheBanner() {
        defer { diagnostics("reconcile-receipts-final") }
        for (argument, receipt) in [("-ui-reconcile-running", "服务器可能还在执行，请稍后再核对"), ("-ui-reconcile-failed", "核对失败，请稍后再试")] {
            launchAndLogin(["-ui-pending-money", argument])
            openAlice()
            check(Self.refund)
            waitForReceipt(receipt)
            XCTAssertFalse(app.alerts.firstMatch.exists, argument)
            XCTAssertTrue(app.buttons["user.pending.check.\(Self.refund)"].waitForExistence(timeout: 5), argument + "\n" + app.debugDescription)
            app.terminate()
        }
    }

    @MainActor func testCompensationRowOpensGrantPendingPage() {
        launchAndLogin(["-ui-pending-compensation-here"])
        defer { diagnostics("reconcile-compensation-final") }
        openAlice()
        XCTAssertTrue(element("user.pending.\(Self.grantHere)").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(labelled(containing: "补偿结果待核对 · $10.00").exists, app.debugDescription)
        check(Self.grantHere)
        // S6-09: the record's 结果待核对 page in the compensation sheet.
        XCTAssertTrue(element("grant.pending").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["补偿结果待核对"].exists, app.debugDescription)
        app.buttons["sheet.close"].tap()
        XCTAssertTrue(element("grant.pending").waitForNonExistence(timeout: 10))
        XCTAssertTrue(element("user.pending.\(Self.grantHere)").exists, app.debugDescription)
    }

    @MainActor func testForegroundExactMatchResolvesOnItsOwn() {
        launchAndLogin(["-ui-pending-money", "-ui-reconcile-executed"])
        defer { diagnostics("reconcile-foreground-final") }
        openAlice()
        let banner = element("user.pending.\(Self.refund)")
        XCTAssertTrue(banner.waitForExistence(timeout: 10), app.debugDescription)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(banner.waitForNonExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(waitUntil(app.staticTexts["receipt.text"], "label BEGINSWITH '已核对'"), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    @MainActor func testForegroundKeepsUnmatchedRecords() {
        launchAndLogin(["-ui-pending-money", "-ui-reconcile-candidate"])
        defer { diagnostics("reconcile-foreground-kept-final") }
        openAlice()
        let banner = element("user.pending.\(Self.refund)")
        XCTAssertTrue(banner.waitForExistence(timeout: 10), app.debugDescription)
        XCUIDevice.shared.press(.home)
        app.activate()
        // A candidate is never settled on its own and asks nothing until the administrator checks.
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(banner.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["user.pending.check.\(Self.refund)"].exists)
    }

    /// The banner is the record's only way to be checked or abandoned, so it stays over a deleted user and a failed profile.
    @MainActor func testBannerStaysWhenTheProfileCannotBeShown() {
        defer { diagnostics("reconcile-profile-missing-final") }
        launchAndLogin(["-ui-pending-money", "-ui-user-detail-fail", "gone", "-ui-reconcile-notfound"])
        openUser(waitingFor: "user.detail.not-found")
        checkAndWaitForAlert(Self.refund, title: "服务器上没有这笔记录").buttons["放弃这笔"].tap()
        let confirm = app.alerts["放弃这笔？"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), app.debugDescription)
        confirm.buttons["放弃这笔"].tap()
        XCTAssertTrue(element("user.pending.\(Self.refund)").waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("user.detail.not-found").exists, app.debugDescription)
        app.terminate()

        launchAndLogin(["-ui-pending-money", "-ui-user-detail-fail", "profile"])
        openUser(waitingFor: "user.detail.error")
        XCTAssertTrue(element("user.pending.\(Self.refund)").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["user.pending.check.\(Self.refund)"].isHittable, app.debugDescription)
        diagnostics("reconcile-profile-failed")
        app.buttons["user.detail.retry"].tap()
        XCTAssertTrue(element("user.hero.balance").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("user.pending.\(Self.refund)").exists, app.debugDescription)
    }

    // MARK: - Helpers

    @MainActor private func launchAndLogin(_ arguments: [String]) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launchQuietly()
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10), app.debugDescription)
        enter("https://reconcile.example.invalid", in: app.textFields["login.url"])
        enter("核对验收", in: app.textFields["login.name"])
        enter("admin@example.com", in: app.textFields["login.email"])
        enter("fixture-password", in: app.secureTextFields["login.password"])
        if app.keyboards.firstMatch.exists {
            app.typeText("\n")
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        }
        tap(submit)
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription)
    }
    /// The user tab → Alice → her detail.
    @MainActor private func openAlice() {
        openUser(waitingFor: "user.hero.balance")
        XCTAssertTrue(app.navigationBars["Alice"].exists, app.debugDescription)
    }
    /// The user tab → Alice's row → the detail in the state named by `identifier`.
    @MainActor private func openUser(waitingFor identifier: String) {
        app.tabBars.buttons["用户"].tap()
        let row = app.buttons["user.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        row.tap()
        XCTAssertTrue(element(identifier).waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func check(_ id: String) {
        let button = app.buttons["user.pending.check.\(id)"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), app.debugDescription)
        button.tap()
    }
    @MainActor @discardableResult
    private func checkAndWaitForAlert(_ id: String, title: String) -> XCUIElement {
        check(id)
        let alert = app.alerts[title]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), title + "\n" + app.debugDescription)
        return alert
    }
    @MainActor private func waitForReceipt(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let receipt = app.staticTexts["receipt.text"]
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: receipt)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, "\(receipt.label) ≠ \(text)\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor private func waitUntil(_ item: XCUIElement, _ format: String) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: item)], timeout: 10) == .completed
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
        // A loop's last launch may have been terminated already.
        guard let app, app.state != .notRunning else { return }
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
