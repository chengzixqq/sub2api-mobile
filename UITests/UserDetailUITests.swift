import XCTest

/// 30 §2 against the `-ui-testing` fixtures (DemoData+Users): Alice (1) has three keys, 24 records and $86.10 this month; Bob (2)
/// has neither keys nor records; 王小明 (3) one active key; 李娜 (4) a low balance; 赵磊 (6) is disabled; 陈思远 (8) an administrator.
/// `-ui-user-detail-fail` breaks single blocks, `-ui-users-self 8` signs in as 陈思远.
final class UserDetailUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testHeroSectionsAndProfile() {
        launchAndLogin()
        defer { diagnostics("user-detail-hero-final") }
        openUser(1, name: "Alice")
        XCTAssertTrue(app.navigationBars["Alice"].staticTexts["alice@example.com"].exists, app.debugDescription)
        let hero = element("user.hero.balance")
        for text in ["可用余额 $12.50", "今日消费 $2.80", "本月 $86.10"] { waitForLabel(hero, contains: text) }
        XCTAssertFalse(hero.label.contains("余额低"), hero.label)
        XCTAssertTrue(app.buttons["user.balance"].isEnabled && app.buttons["user.refund"].isEnabled)
        waitForValue(element("user.keys.header"), equals: "3 个 · 活跃 1")
        let keys = app.buttons["user.keys"]
        for text in ["开发密钥、脚本、备用", "标准组、未绑定分组 · 脚本 已停用、备用 额度耗尽 · 最近使用 3 分钟前"] { waitForLabel(keys, contains: text) }
        XCTAssertTrue(app.scrollUntilExists(element("user.ledger.header")))
        waitForValue(element("user.ledger.header"), equals: "总充值 $70.00")
        let all = app.buttons["user.ledger.all"]
        XCTAssertTrue(app.scrollUntilExists(all))
        XCTAssertTrue(all.label.contains("全部 24 条"), all.label)
        for id in [124, 123, 122, -7, 121] { XCTAssertTrue(element("user.ledger.row.\(id)").exists, "\(id)\n\(app.debugDescription)") }
        XCTAssertFalse(element("user.ledger.row.120").exists, app.debugDescription)
        let profile = element("user.profile.concurrency")
        XCTAssertTrue(app.scrollUntilExists(profile))
        for (id, value) in [("id", "1"), ("status", "启用"), ("role", "用户"), ("concurrency", "2")] {
            XCTAssertEqual(element("user.profile.\(id)").value as? String, value, id)
        }
    }

    @MainActor func testLowBalanceDisabledAndEmptyKeys() {
        launchAndLogin()
        defer { diagnostics("user-detail-marks-final") }
        openUser(4, name: "李娜")
        waitForLabel(element("user.hero.balance"), contains: "余额低")
        XCTAssertFalse(element("user.disabled").exists)
        goBack()
        openUser(6, name: "赵磊")
        let banner = element("user.disabled")
        XCTAssertTrue(banner.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["user.disabled.enable"].exists, app.debugDescription)
        let status = element("user.profile.status")
        XCTAssertTrue(app.scrollUntilExists(status))
        XCTAssertEqual(status.value as? String, "禁用")
        goBack()
        openUser(2, name: "Bob")
        waitForValue(element("user.keys.header"), equals: "0 个")
        waitForLabel(app.buttons["user.keys"], contains: "还没有 Key")
        XCTAssertTrue(app.buttons["user.keys"].label.contains("可以在编辑用户里新建"), app.buttons["user.keys"].label)
        let empty = element("user.ledger.peek.empty")
        XCTAssertTrue(app.scrollUntilExists(empty))
        XCTAssertEqual(empty.label, "暂无记录")
        XCTAssertEqual(element("user.ledger.header").value as? String ?? "", "")
        XCTAssertFalse(app.buttons["user.ledger.all"].exists)
    }

    @MainActor func testMenuItemsFollowRole() {
        launchAndLogin()
        defer { diagnostics("user-detail-menu-final") }
        openUser(3, name: "王小明")
        openMenu()
        for title in ["编辑用户", "禁用用户", "发放兑换码（补偿）…", "删除用户…"] {
            XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 3), "\(title)\n\(app.debugDescription)")
        }
        XCTAssertFalse(labelled("管理员不能禁用或删除。").exists)
        app.buttons["发放兑换码（补偿）…"].tap()
        XCTAssertTrue(app.navigationBars["发放兑换码（补偿）"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["sheet.close"].tap()
        XCTAssertTrue(app.navigationBars["发放兑换码（补偿）"].waitForNonExistence(timeout: 5), app.debugDescription)
        goBack()
        openUser(8, name: "陈思远")
        openMenu()
        XCTAssertTrue(app.buttons["编辑用户"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.buttons["发放兑换码（补偿）…"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["禁用用户"].exists || app.buttons["删除用户…"].exists, app.debugDescription)
        XCTAssertTrue(labelled("管理员不能禁用或删除。").exists, app.debugDescription)
        app.buttons["编辑用户"].tap()
        XCTAssertTrue(element("user-editor.email").waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["user-editor.close"].tap()
        XCTAssertTrue(element("user-editor.email").waitForNonExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testSelfMenuNote() {
        launchAndLogin(arguments: ["-ui-users-self", "8"])
        defer { diagnostics("user-detail-self-final") }
        openUser(8, name: "陈思远")
        let role = element("user.profile.role")
        XCTAssertTrue(app.scrollUntilExists(role))
        XCTAssertEqual(role.value as? String, "管理员 · 你")
        openMenu()
        XCTAssertTrue(labelled("这是你当前登录的账号。管理员不能禁用或删除。").waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.buttons["编辑用户"].exists && app.buttons["发放兑换码（补偿）…"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["禁用用户"].exists || app.buttons["删除用户…"].exists, app.debugDescription)
    }

    @MainActor func testDisableReceiptUndoAndEnableFromBanner() {
        launchAndLogin()
        defer { diagnostics("user-detail-disable-final") }
        openUser(3, name: "王小明")
        chooseFromMenu("禁用用户")
        waitForReceipt("已禁用 王小明 · 1 个 Key 停止调用")
        XCTAssertTrue(element("user.disabled").waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["receipt.action"].tap()
        XCTAssertTrue(element("user.disabled").waitForNonExistence(timeout: 10), app.debugDescription)
        waitForReceipt("已启用 王小明")
        XCTAssertFalse(app.buttons["receipt.action"].exists, app.debugDescription)
        chooseFromMenu("禁用用户")
        XCTAssertTrue(element("user.disabled").waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["user.disabled.enable"].tap()
        XCTAssertTrue(element("user.disabled").waitForNonExistence(timeout: 10), app.debugDescription)
        waitForReceipt("已启用 王小明")
        chooseFromMenu("禁用用户")
        XCTAssertTrue(element("user.disabled").waitForExistence(timeout: 10), app.debugDescription)
        goBack()
        waitForLabel(app.buttons["user.3"], contains: "禁用")
    }

    @MainActor func testDisableFailureForProtectedAdminShowsServerRefusal() {
        launchAndLogin(arguments: ["-ui-user-detail-fail", "status"])
        defer { diagnostics("user-detail-status-failure-final") }
        openUser(3, name: "王小明")
        chooseFromMenu("禁用用户")
        waitForReceipt("操作失败：服务器未能完成请求")
        XCTAssertFalse(element("user.disabled").exists, app.debugDescription)
        let status = element("user.profile.status")
        XCTAssertTrue(app.scrollUntilExists(status))
        XCTAssertEqual(status.value as? String, "启用")
    }

    @MainActor func testDeleteByTypingName() {
        launchAndLogin()
        defer { diagnostics("user-detail-delete-final") }
        openUser(3, name: "王小明")
        chooseFromMenu("删除用户…")
        let title = element("delete.title")
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(title.label, "删除用户「王小明」？")
        let message = element("delete.message").label
        for line in ["站点 用户详情验收", "名下 1 个 Key 一并删除。"] { XCTAssertTrue(message.contains(line), message) }
        XCTAssertFalse(message.contains("删除后不能恢复"), message)
        let confirm = app.buttons["delete.confirm"]
        XCTAssertFalse(confirm.isEnabled)
        let input = element("delete.input")
        input.tap()
        input.typeText("王小")
        XCTAssertFalse(confirm.isEnabled)
        input.typeText("明")
        XCTAssertTrue(waitUntil(confirm, "isEnabled == true"), app.debugDescription)
        confirm.tap()
        XCTAssertTrue(app.navigationBars["王小明"].waitForNonExistence(timeout: 10), app.debugDescription)
        waitForReceipt("已删除用户「王小明」")
        XCTAssertFalse(app.buttons["receipt.action"].exists, app.debugDescription)
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["user.3"].exists, app.debugDescription)
    }

    @MainActor func testDeleteWithFaceIDWhenEnabled() {
        launchAndLogin(arguments: ["-ui-faceid-on", "-ui-biometric-deny"])
        openUser(3, name: "王小明")
        chooseFromMenu("删除用户…")
        let confirm = app.buttons["delete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(confirm.label, "用 Face ID 删除")
        XCTAssertFalse(element("delete.input").exists)
        confirm.tap()
        // A refused check deletes nothing and says nothing (60 §3.4).
        XCTAssertTrue(waitUntil(confirm, "isEnabled == true"), app.debugDescription)
        app.buttons["delete.cancel"].tap()
        XCTAssertTrue(element("delete.sheet").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.navigationBars["王小明"].exists, app.debugDescription)
        diagnostics("user-detail-faceid-denied")
        app.terminate()
        launchAndLogin(arguments: ["-ui-faceid-on"])
        defer { diagnostics("user-detail-faceid-final") }
        openUser(3, name: "王小明")
        chooseFromMenu("删除用户…")
        XCTAssertTrue(app.buttons["delete.confirm"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["delete.confirm"].tap()
        waitForReceipt("已删除用户「王小明」")
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["user.3"].exists, app.debugDescription)
    }

    @MainActor func testAllRecordsLinkOpensLedger() {
        launchAndLogin()
        defer { diagnostics("user-detail-ledger-final") }
        openUser(1, name: "Alice")
        let all = app.buttons["user.ledger.all"]
        XCTAssertTrue(app.scrollUntilExists(all))
        all.tap()
        XCTAssertTrue(app.navigationBars["充值与调整记录"].waitForExistence(timeout: 10), app.debugDescription)
        waitForLabel(element("user.ledger.count"), contains: "24 条")
    }

    @MainActor func testKeySummaryOpensEditPlaceholderAndLogsRow() {
        launchAndLogin()
        defer { diagnostics("user-detail-links-final") }
        openUser(1, name: "Alice")
        let keys = app.buttons["user.keys"]
        XCTAssertTrue(keys.waitForExistence(timeout: 10), app.debugDescription)
        keys.tap()
        XCTAssertTrue(app.navigationBars["编辑用户"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("route.placeholder").exists, app.debugDescription)
        goBack()
        let logs = app.buttons["user.logs"]
        XCTAssertTrue(app.scrollUntilExists(logs))
        XCTAssertTrue(logs.label.contains("使用记录"), logs.label)
        logs.tap()
        XCTAssertTrue(app.navigationBars["Alice"].waitForNonExistence(timeout: 10), app.debugDescription)
        goBack()
        XCTAssertTrue(app.navigationBars["Alice"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testBlockFailuresAreIndependentAndRetry() {
        launchAndLogin(arguments: ["-ui-user-detail-fail", "today,month,keys,ledger"])
        defer { diagnostics("user-detail-blocks-final") }
        openUser(1, name: "Alice")
        let hero = element("user.hero.balance")
        waitForLabel(hero, contains: "可用余额 $12.50")
        for id in ["user.hero.today", "user.hero.month", "user.keys"] {
            XCTAssertTrue(element("\(id).failure").waitForExistence(timeout: 10), "\(id)\n\(app.debugDescription)")
        }
        XCTAssertTrue(hero.label.contains("今日消费 无数据") && !hero.label.contains("本月"), hero.label)
        XCTAssertFalse(element("user.keys.header").value as? String == "3 个 · 活跃 1")
        app.buttons["user.hero.today.retry"].tap()
        waitForLabel(hero, contains: "今日消费 $2.80")
        XCTAssertTrue(element("user.hero.month.failure").exists, app.debugDescription)
        app.buttons["user.hero.month.retry"].tap()
        waitForLabel(hero, contains: "本月 $86.10")
        app.buttons["user.keys.retry"].tap()
        waitForValue(element("user.keys.header"), equals: "3 个 · 活跃 1")
        let ledger = element("user.ledger.peek.failure")
        XCTAssertTrue(app.scrollUntilExists(ledger))
        app.buttons["user.ledger.peek.retry"].tap()
        XCTAssertTrue(element("user.ledger.row.124").waitForExistence(timeout: 10), app.debugDescription)
        diagnostics("user-detail-blocks")
        app.terminate()
        launchAndLogin(arguments: ["-ui-user-detail-fail", "profile"])
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["user.1"].tap()
        let error = element("user.detail.error")
        XCTAssertTrue(error.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(error.label, "加载用户失败")
        app.buttons["user.detail.retry"].tap()
        XCTAssertTrue(app.navigationBars["Alice"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("user.hero.balance").waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testDeletedUserShowsNotFoundAndLeavesList() {
        launchAndLogin(arguments: ["-ui-user-detail-fail", "gone"])
        defer { diagnostics("user-detail-gone-final") }
        app.tabBars.buttons["用户"].tap()
        let row = app.buttons["user.3"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), app.debugDescription)
        row.tap()
        let missing = element("user.detail.not-found")
        XCTAssertTrue(missing.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(missing.label, "这个用户不存在或已删除")
        XCTAssertFalse(app.buttons["user.more"].exists)
        app.buttons["user.detail.back"].tap()
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["user.3"].exists, app.debugDescription)
    }

    @MainActor func testReadOnlyTokenGraysWritesAndHidesToday() {
        launchAndLogin(arguments: ["-ui-readonly-token"], accessToken: "sat_fixture-readonly")
        defer { diagnostics("user-detail-read-only-final") }
        openUser(1, name: "Alice")
        let hero = element("user.hero.balance")
        waitForLabel(hero, contains: "本月 $86.10")
        XCTAssertTrue(hero.label.contains("今日消费 无数据"), hero.label)
        XCTAssertFalse(element("user.hero.today.failure").exists, app.debugDescription)
        XCTAssertFalse(app.buttons["user.balance"].isEnabled)
        XCTAssertFalse(app.buttons["user.refund"].isEnabled)
        XCTAssertTrue(element("readonly.caption").exists, app.debugDescription)
        openMenu()
        for title in ["编辑用户", "禁用用户", "发放兑换码（补偿）…", "删除用户…"] {
            let item = app.buttons[title]
            XCTAssertTrue(item.waitForExistence(timeout: 3), "\(title)\n\(app.debugDescription)")
            XCTAssertFalse(item.isEnabled, title)
        }
    }

    /// 30 §2.6: back from the editor (here the key summary's push) the profile, the keys and the records are read again, so a
    /// failed records block recovers without 重试.
    @MainActor func testReturnFromEditorRereadsRecords() {
        launchAndLogin(arguments: ["-ui-user-detail-fail", "ledger"])
        defer { diagnostics("user-detail-editor-return-final") }
        openUser(1, name: "Alice")
        XCTAssertTrue(app.scrollUntilExists(element("user.ledger.peek.failure")))
        let keys = app.buttons["user.keys"]
        XCTAssertTrue(app.scrollUntilExists(keys, towardBottom: false))
        keys.tap()
        XCTAssertTrue(app.navigationBars["编辑用户"].waitForExistence(timeout: 10), app.debugDescription)
        goBack()
        XCTAssertTrue(app.navigationBars["Alice"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.scrollUntilExists(element("user.ledger.row.124")))
        XCTAssertFalse(element("user.ledger.peek.failure").exists, app.debugDescription)
    }

    // MARK: - Helpers

    /// Password sign-in, or the access-token method for `accessToken` (a `sat_` key selects it on its own, 60 §4.3), so
    /// `-ui-readonly-token` makes the session read-only.
    @MainActor private func launchAndLogin(arguments: [String] = [], accessToken: String? = nil) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10), app.debugDescription)
        enter("https://user-detail.example.invalid", in: app.textFields["login.url"])
        enter("用户详情验收", in: app.textFields["login.name"])
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
    @MainActor private func goBack() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }
    @MainActor private func openMenu() {
        let more = app.buttons["user.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), app.debugDescription)
        more.tap()
    }
    /// System menu items carry no identifiers; they are found by their words.
    @MainActor private func chooseFromMenu(_ title: String) {
        openMenu()
        let item = app.buttons[title]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "\(title)\n\(app.debugDescription)")
        item.tap()
    }
    @MainActor private func waitForReceipt(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let receipt = app.staticTexts["receipt.text"]
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: receipt)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: 10), .completed, "\(receipt.label) ≠ \(text)\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor private func waitForLabel(_ item: XCUIElement, contains text: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, "\(item.label) ∌ \(text)\n\(app.debugDescription)",
                       file: file, line: line)
    }
    @MainActor private func waitForValue(_ item: XCUIElement, equals text: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: item)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed,
                       "\(item.value as? String ?? "nil") ≠ \(text)\n\(app.debugDescription)", file: file, line: line)
    }
    @MainActor private func waitUntil(_ item: XCUIElement, _ format: String) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: item)], timeout: 5) == .completed
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func labelled(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
    @MainActor private func tap(_ item: XCUIElement) { reveal(item); item.tap() }
    @MainActor private func enter(_ value: String, in field: XCUIElement) { tap(field); field.typeText(value) }
    /// The login form: drags above the keyboard, toward a field already passed or further down, until it can be tapped.
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
