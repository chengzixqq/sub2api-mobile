import XCTest

/// S6-09: the compensation sheet (60 §19) and its pending page against the `-ui-testing` fixtures, offline. 王小明 (3) has $12.40,
/// concurrency 1 and an active 企业专线 (group 4) subscription; `-ui-pending-compensation-here` gives Alice (1) a $10.00
/// compensation of this site (0C…01), `-ui-pending-old-site` Bob (2) an $8.00 one of an older login at this address (0B…03);
/// `-ui-reconcile-*` decides what a check finds (S6-08), `-ui-grant-*` what a grant answers (RedeemFixtures). A code is only
/// ever asserted by its short form.
final class RedeemGrantUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!
    private static let grantHere = "0C000000-0000-4000-8000-000000000001"
    private static let menuItem = "发放兑换码（补偿）…"
    private static let blockTitle = "上一次补偿的发放结果未确认"

    @MainActor func testSettingsRowOpensPendingPageAndChecks() {
        launchAndLogin(["-ui-pending-compensation-here", "-ui-reconcile-executed"])
        defer { diagnostics("grant-settings-check-final") }
        openSettingsRow(Self.grantHere)
        XCTAssertTrue(element("grant.pending").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["补偿结果待核对"].exists, app.debugDescription)
        XCTAssertEqual(element("grant.pending.header.title").label, "请求可能已提交")
        XCTAssertTrue(element("money.pending.receipt.code").label.contains("FIXT····0C01"), element("money.pending.receipt.code").label)
        XCTAssertTrue(element("money.pending.receipt.key").label.contains(Self.grantHere.lowercased()), app.debugDescription)
        XCTAssertFalse(labelled(containing: "FIXTURE-GRANT-0C01").exists, app.debugDescription)
        XCTAssertTrue(app.buttons["grant.pending.retry"].isEnabled, app.debugDescription)
        diagnostics("grant-pending-page")
        app.buttons["grant.pending.check"].tap()
        waitForReceipt("已核对：已向 Alice 发放 $10.00 余额")
        XCTAssertTrue(element("grant.pending").waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("settings.pending.compensation.\(Self.grantHere)").exists, app.debugDescription)
    }

    /// X38: the menu asks first; 取消 opens nothing, 先核对 that record's page. Nothing found offers the retry or giving up.
    @MainActor func testBlockAlertNotFoundAndAbandon() {
        launchAndLogin(["-ui-pending-compensation-here", "-ui-reconcile-notfound"])
        defer { diagnostics("grant-abandon-final") }
        openUser(1, name: "Alice")
        chooseFromMenu(Self.menuItem)
        var alert = app.alerts[Self.blockTitle]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(labelled(containing: "向 Alice 发放 $10.00 余额 · 2 分钟前发起。", in: alert).exists, app.debugDescription)
        alert.buttons["取消"].tap()
        XCTAssertFalse(element("grant.pending").waitForExistence(timeout: 2), app.debugDescription)
        XCTAssertFalse(element("grant.sheet").exists, app.debugDescription)
        chooseFromMenu(Self.menuItem)
        alert = app.alerts[Self.blockTitle]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        alert.buttons["先核对"].tap()
        XCTAssertTrue(element("grant.pending").waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["grant.pending.check"].tap()
        waitForLabel(element("grant.pending.header.title"), equals: "服务器上没有这次发放")
        XCTAssertTrue(app.buttons["grant.pending.retry"].exists && app.buttons["grant.pending.abandon"].exists, app.debugDescription)
        app.buttons["grant.pending.abandon"].tap()
        let confirm = app.alerts["放弃这次发放？"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(labelled(containing: "放弃后这笔不会再重试；如果服务器其实已经发放，以服务器为准。", in: confirm).exists, app.debugDescription)
        confirm.buttons["放弃这次发放"].tap()
        waitForReceipt("已放弃 · 不再提醒")
        XCTAssertTrue(element("user.pending.\(Self.grantHere)").waitForNonExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testUnusedCodeRetriesWithTheSameNumber() {
        launchAndLogin(["-ui-pending-compensation-here", "-ui-reconcile-unused"])
        defer { diagnostics("grant-unused-final") }
        openSettingsRow(Self.grantHere)
        XCTAssertTrue(element("grant.pending").waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["grant.pending.check"].tap()
        waitForLabel(element("grant.pending.header.title"), equals: "兑换码已创建，还没兑换给 Alice")
        XCTAssertEqual(element("grant.pending.footnote").label, "放弃后这个码留在兑换码列表里，未使用，可以删除。")
        app.buttons["grant.pending.retry"].tap()
        waitForReceipt("已向 Alice 发放 $10.00 余额")
        XCTAssertTrue(element("grant.pending").waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("settings.pending.compensation.\(Self.grantHere)").exists, app.debugDescription)
    }

    /// X34 + X38: an older login's record at this address blocks Bob's new compensation too; another administrator's record is
    /// only checked or given up.
    @MainActor func testOtherAdministratorsOldLoginRecordFromUserDetail() {
        launchAndLogin(["-ui-pending-old-site", "-ui-pending-other-actor"])
        defer { diagnostics("grant-old-login-final") }
        openUser(2, name: "Bob")
        chooseFromMenu(Self.menuItem)
        let alert = app.alerts[Self.blockTitle]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(labelled(containing: "向 Bob 发放 $8.00 余额 · 10 分钟前发起。", in: alert).exists, app.debugDescription)
        alert.buttons["先核对"].tap()
        XCTAssertTrue(element("grant.pending").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("money.pending.receipt.site").label.contains("本站点的旧登录下发起"), element("money.pending.receipt.site").label)
        XCTAssertFalse(app.buttons["grant.pending.retry"].exists, app.debugDescription)
        XCTAssertTrue(app.buttons["grant.pending.abandon"].exists && app.buttons["grant.pending.check"].isEnabled, app.debugDescription)
        waitForLabel(element("grant.pending.notes"), contains: "只能由同一管理员重试；可以放弃后重新发放。")
    }

    @MainActor func testBalanceGrantFromUserDetail() {
        launchAndLogin([])
        defer { diagnostics("grant-balance-final") }
        openGrantSheet(userID: 3, name: "王小明")
        XCTAssertTrue(app.navigationBars["发放兑换码"].exists, app.debugDescription)
        waitForLabel(element("grant.subject"), contains: "王小明 · xm.wang@example.com")
        app.buttons["grant.type.balance"].tap()
        XCTAssertTrue(app.navigationBars["余额补偿"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(element("grant.preview").label, "输入金额")
        XCTAssertFalse(app.buttons["grant.next"].isEnabled)
        typeAmount("10")
        waitForLabel(element("grant.preview"), contains: "$22.40")
        app.buttons["grant.next"].tap()
        XCTAssertTrue(app.navigationBars["备注与确认"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(element("money.pending.receipt.change").label.contains("余额 $12.40 → $22.40"), element("money.pending.receipt.change").label)
        XCTAssertTrue(element("money.pending.receipt.code").label.contains("····"), app.debugDescription)
        revealInSheet(element("grant.rebate"))
        XCTAssertFalse(element("grant.faceid.note").exists, app.debugDescription)
        let submit = app.buttons["grant.submit"]
        XCTAssertEqual(submit.label, "发放 $10.00")
        diagnostics("grant-balance-step3")
        submit.tap()
        let alert = app.alerts["向「王小明」发放 $10.00 余额？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(labelled(containing: "站点 补偿验收 · 余额 $12.40 → $22.40", in: alert).exists, app.debugDescription)
        alert.buttons["发放 $10.00"].tap()
        waitForReceipt("已向 王小明 发放 $10.00 余额")
        XCTAssertTrue(element("grant.sheet").waitForNonExistence(timeout: 10), app.debugDescription)
        // 查看兑换码 opens the list on the new code (60 §19.1), on the user tab's stack.
        app.buttons["receipt.action"].tap()
        XCTAssertTrue(element("redeem.card.95001").waitForExistence(timeout: 10), app.debugDescription)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        waitForLabel(element("user.hero.balance"), contains: "可用余额 $22.40")
    }

    @MainActor func testFaceIDThresholdAndDeny() {
        launchAndLogin(["-ui-faceid-on", "-ui-biometric-deny"])
        defer { diagnostics("grant-faceid-final") }
        openGrantSheet(userID: 3, name: "王小明")
        app.buttons["grant.type.balance"].tap()
        typeAmount("150")
        app.buttons["grant.next"].tap()
        let note = element("grant.faceid.note")
        revealInSheet(note)
        XCTAssertEqual(note.label, "超过 $100，确认后验证 Face ID。")
        app.buttons["grant.submit"].tap()
        let alert = app.alerts["向「王小明」发放 $150.00 余额？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(labelled(containing: "超过 $100，确认后验证 Face ID。", in: alert).exists, app.debugDescription)
        alert.buttons["发放 $150.00"].tap()
        // Denied: nothing saved, nothing sent; the sheet stays on step 3.
        waitForLabel(app.buttons["grant.submit"], equals: "发放 $150.00")
        XCTAssertFalse(app.staticTexts["receipt.text"].exists, app.debugDescription)
        app.buttons["grant.back"].tap()
        app.buttons["grant.back"].tap()
        app.buttons["sheet.close"].tap()
        XCTAssertTrue(element("grant.sheet").waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'user.pending.'")).count, 0, app.debugDescription)
    }

    /// U52: an unlimited user's concurrency tile is grey with its reason; the subscription step names the plan.
    @MainActor func testUnlimitedConcurrencyAndSubscriptionPlan() {
        launchAndLogin(["-ui-grant-unlimited"])
        defer { diagnostics("grant-plan-final") }
        openGrantSheet(userID: 3, name: "王小明")
        let tile = app.buttons["grant.type.concurrency"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(tile.value as? String, "这个用户并发不限制，发放后反而会变成有上限")
        tile.tap()
        XCTAssertTrue(app.navigationBars["发放兑换码"].exists, app.debugDescription)
        app.buttons["grant.type.subscription"].tap()
        XCTAssertTrue(app.navigationBars["订阅补偿"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["grant.group.4"].exists, app.debugDescription)
        waitForLabel(element("grant.plan"), contains: "已有生效中的订阅：在原到期日 ")
        waitForLabel(element("grant.subject"), contains: "企业专线 至 ")
        app.buttons["grant.days.90"].tap()
        app.buttons["grant.next"].tap()
        XCTAssertTrue(app.navigationBars["备注与确认"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.buttons["grant.submit"].label, "发放 90 天订阅")
        XCTAssertTrue(element("money.pending.receipt.value").label.contains("企业专线 · 90 天"), app.debugDescription)
        XCTAssertFalse(element("grant.rebate").exists, app.debugDescription)
    }

    /// The subscriptions cannot be read: the fallback line, not a block. A lost answer turns the sheet into the pending page and
    /// the record stays, so the detail's banner shows it after the sheet closes.
    @MainActor func testUnknownResultTurnsIntoPendingPage() {
        launchAndLogin(["-ui-grant-subs-error", "-ui-grant-unknown"])
        defer { diagnostics("grant-unknown-final") }
        openGrantSheet(userID: 3, name: "王小明")
        app.buttons["grant.type.subscription"].tap()
        waitForLabel(element("grant.plan"), equals: "暂时读不到这个用户的订阅，发放后以服务器结果为准")
        XCTAssertTrue(app.buttons["grant.next"].isEnabled, app.debugDescription)
        app.buttons["grant.next"].tap()
        let submit = app.buttons["grant.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(submit.label, "发放 30 天订阅")
        submit.tap()
        let alert = app.alerts["向「王小明」发放 企业专线 30 天订阅？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        alert.buttons["发放 30 天订阅"].tap()
        XCTAssertTrue(element("grant.pending").waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(element("grant.pending.header.title").label, "请求可能已提交")
        app.buttons["sheet.close"].tap()
        XCTAssertTrue(element("grant.pending").waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(labelled(containing: "补偿结果待核对").waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testReadOnlyTokenCannotRetry() {
        launchAndLogin(["-ui-pending-compensation-here", "-ui-readonly-token"], accessToken: "sat_fixture-readonly")
        defer { diagnostics("grant-read-only-final") }
        openSettingsRow(Self.grantHere)
        XCTAssertTrue(element("grant.pending").waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["grant.pending.check"].isEnabled, app.debugDescription)
        XCTAssertTrue(app.buttons["grant.pending.retry"].exists && !app.buttons["grant.pending.retry"].isEnabled, app.debugDescription)
        waitForLabel(element("grant.pending.notes"), equals: "当前登录的是只读令牌，不能修改")
    }

    /// A refused group (60 §19.4): back to step 2 with the group it went out with still chosen; the server made the code with
    /// that group before refusing it, so the code stays only while nothing changes (step 5).
    @MainActor func testRefusedGroupKeepsItsGroupUntilAnEdit() {
        launchAndLogin(["-ui-grant-group-gone"])
        defer { diagnostics("grant-group-gone-final") }
        openGrantSheet(userID: 3, name: "王小明")
        app.buttons["grant.type.subscription"].tap()
        XCTAssertTrue(app.buttons["grant.group.4"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["grant.next"].tap()
        let code = element("money.pending.receipt.code")
        XCTAssertTrue(code.waitForExistence(timeout: 5), app.debugDescription)
        let sent = code.label
        app.buttons["grant.submit"].tap()
        let alert = app.alerts["向「王小明」发放 企业专线 30 天订阅？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        alert.buttons["发放 30 天订阅"].tap()
        XCTAssertTrue(app.navigationBars["订阅补偿"].waitForExistence(timeout: 10), app.debugDescription)
        waitForLabel(element("grant.notice"), contains: "这个分组不能用于订阅，请重新选择")
        XCTAssertTrue(app.buttons["grant.group.4"].isSelected, app.debugDescription)
        app.buttons["grant.next"].tap()
        XCTAssertTrue(code.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(code.label, sent, app.debugDescription)
        app.buttons["grant.back"].tap()
        app.buttons["grant.days.90"].tap()
        app.buttons["grant.next"].tap()
        XCTAssertTrue(code.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertNotEqual(code.label, sent, app.debugDescription)
        XCTAssertTrue(code.label.contains("····"), code.label)
    }

    // MARK: - Helpers

    /// Password sign-in, or the access-token method for `accessToken` (a `sat_` key selects it on its own, 60 §4.3).
    @MainActor private func launchAndLogin(_ arguments: [String], accessToken: String? = nil) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launchQuietly()
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10), app.debugDescription)
        enter("https://grant.example.invalid", in: app.textFields["login.url"])
        enter("补偿验收", in: app.textFields["login.name"])
        if let accessToken {
            tap(app.buttons["login.method.adminKey"])
            enter(accessToken, in: app.secureTextFields["login.key"])
        } else {
            enter("admin@example.com", in: app.textFields["login.email"])
            enter("fixture-password", in: app.secureTextFields["login.password"])
        }
        if app.keyboards.firstMatch.exists {
            app.typeText("\n")
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        }
        tap(submit)
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription)
    }
    /// The user tab → the row (scrolled to) → the detail with the name as its title.
    @MainActor private func openUser(_ id: Int, name: String) {
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10), app.debugDescription)
        let row = app.buttons["user.\(id)"]
        app.scrollUntilExists(row)
        row.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("user.hero.balance").waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func openGrantSheet(userID: Int, name: String) {
        openUser(userID, name: name)
        chooseFromMenu(Self.menuItem)
        XCTAssertTrue(element("grant.sheet").waitForExistence(timeout: 10), app.debugDescription)
    }
    /// System menu items carry no identifiers; they are found by their words.
    @MainActor private func chooseFromMenu(_ title: String) {
        let more = app.buttons["user.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), app.debugDescription)
        more.tap()
        let item = app.buttons[title]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "\(title)\n\(app.debugDescription)")
        item.tap()
    }
    /// Settings → 站点与凭据 → the record's “去核对 ›”, below the current site (a List builds rows only near the screen).
    @MainActor private func openSettingsRow(_ id: String) {
        app.openSitesSettings()
        let check = element("settings.pending.check.\(id)")
        app.scrollUntilExists(check)
        check.tap()
    }
    @MainActor private func typeAmount(_ digits: String) {
        for digit in digits { app.buttons["grant.keypad.key.\(digit)"].tap() }
    }
    /// The sheet covers the tab bar, so it is scrolled up by drags inside it; never down, which would pull the sheet away.
    @MainActor private func revealInSheet(_ item: XCUIElement) {
        for _ in 0..<5 where !(item.exists && item.isHittable) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        }
        XCTAssertTrue(item.exists, app.debugDescription)
    }
    @MainActor private func waitForReceipt(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let receipt = app.staticTexts["receipt.text"]
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: receipt)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 15), .completed, "\(receipt.label) ≠ \(text)\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor private func waitForLabel(_ item: XCUIElement, contains text: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, "\(item.label) ∌ \(text)\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor private func waitForLabel(_ item: XCUIElement, equals text: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, "\(item.label) ≠ \(text)\n\(app.debugDescription)", file: file, line: line)
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
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
