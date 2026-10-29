import XCTest

final class Sub2MobileUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!
    @MainActor private func launch(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
    }

    @MainActor func testLoginRequiresHTTPSAndCredentials() {
        launch()
        submitLogin()
        XCTAssertTrue(app.staticTexts["login.error"].exists)
        enter("测试站点", in: app.textFields["login.name"], towardBottom: false)
        enter("http://example.com", in: app.textFields["login.url"])
        submitLogin()
        XCTAssertTrue(app.staticTexts["login.error"].label.contains("HTTPS"))
    }

    @MainActor func testLoginShowsDashboard() {
        launch()
        login(name: "站点 A", url: "https://a.example.com")
        // S1-09: the overview's six cells.
        XCTAssertTrue(app.descendants(matching: .any)["home.ticker"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testAccountPaginationAndDetails() {
        launch()
        login(name: "站点 A", url: "https://a.example.com")
        app.tabBars.buttons["账号"].tap()
        XCTAssertTrue(app.buttons["account.1"].waitForExistence(timeout: 10))
        // S2-04: the list reads every page itself; both accounts sit in the Anthropic section.
        reveal(app.buttons["account.2"])
        reveal(app.buttons["account.1"], towardBottom: false)
        app.buttons["account.1"].tap()
        // S2-08: the new detail; S2-14: 测试连接 opens the test sheet, which starts at once (20 §4.4, no start button).
        let card = app.descendants(matching: .any)["account.detail.card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), app.debugDescription)
        reveal(app.buttons["account.action.test"])
        app.buttons["account.action.test"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["account.test.sheet"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["account.test.output"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["account.test.start"].exists)
        app.buttons["sheet.close"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testUserPaginationAndMaskedKeys() {
        launch()
        login(name: "站点 A", url: "https://a.example.com")
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10))
        // 30 §1.4: the second page loads when its last row scrolls in; there is no “加载更多” button.
        XCTAssertFalse(app.buttons["users.more"].exists)
        XCTAssertFalse(app.buttons["user.26"].exists)
        XCTAssertTrue(app.scrollUntilExists(app.buttons["user.26"], maxSwipes: 16))
        XCTAssertTrue(app.scrollUntilExists(app.buttons["user.1"], towardBottom: false, maxSwipes: 16))
        app.buttons["user.1"].tap()
        // S3-05: the detail shows one key summary; the masks are checked on S3-12's key cards.
        XCTAssertTrue(app.navigationBars["Alice"].waitForExistence(timeout: 10))
        reveal(app.buttons["user.balance"])
        XCTAssertFalse(app.staticTexts["sk-fixture-secret"].exists)
    }

    @MainActor func testAddAndSwitchStations() {
        launch()
        login(name: "站点 A", url: "https://a.example.com")
        app.openSitesSettings()
        app.buttons["settings.add"].tap()
        login(name: "站点 B", url: "https://b.example.com")
        app.openSitesSettings()
        XCTAssertTrue(app.buttons["settings.site.站点 A"].waitForExistence(timeout: 10))
        app.buttons["settings.site.站点 A"].tap()
        // 10 §0.7-5: the switch ends with a receipt that outlives the rebuilt tabs.
        let receipt = app.staticTexts["receipt.text"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(receipt.label, "已切换到 站点 A")
        app.tabBars.buttons["概览"].tap()
        XCTAssertTrue(app.navigationBars["站点 A"].waitForExistence(timeout: 10))
    }

    @MainActor func testSameStationKeepsNewLoginAsSeparateIdentity() {
        launch()
        login(name: "管理员 A", url: "https://same.example.com")
        app.openSitesSettings()
        app.buttons["settings.add"].tap()
        login(name: "管理员 B", url: "https://same.example.com")
        app.openSitesSettings()
        XCTAssertTrue(app.buttons["settings.site.管理员 A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.site.管理员 B"].exists)
    }

    @MainActor func testLogoutErasesCredentialInsteadOfRestoringSession() {
        launch()
        login(name: "站点 A", url: "https://a.example.com")
        app.openSitesSettings()
        // S0-15: the row now reads like the dialog's button, so the button is told apart by its missing identifier.
        reveal(app.buttons["settings.logout"])
        app.buttons["settings.logout"].tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "退出并清除凭据", "settings.logout")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()
        XCTAssertTrue(app.buttons["login.submit"].waitForExistence(timeout: 10))
        reveal(app.buttons["login.saved.站点 A"])
        app.buttons["login.saved.站点 A"].tap()
        // The site's own login page, prefilled, instead of an error alert (00 §1.1).
        XCTAssertTrue(app.staticTexts["login.notice"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["login.notice"].label, "此站点凭据已清除，请重新登录。")
        XCTAssertEqual(app.textFields["login.name"].value as? String, "站点 A")
        XCTAssertEqual(app.textFields["login.url"].value as? String, "https://a.example.com")
        XCTAssertFalse(app.tabBars.buttons["概览"].exists)
        // Signing in again keeps the same site instead of adding a second “站点 A”.
        enter("admin@example.com", in: app.textFields["login.email"])
        enter("fixture-password", in: app.secureTextFields["login.password"])
        submitLogin()
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10))
        app.openSitesSettings()
        XCTAssertTrue(app.buttons["settings.site.站点 A"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "settings.site.站点 A").count, 1)
    }

    @MainActor func testRemovingActiveStationReturnsToLoginWithoutIt() {
        launch()
        login(name: "站点 A", url: "https://a.example.com")
        app.openSitesSettings()
        XCTAssertTrue(app.buttons["settings.site.more.站点 A"].waitForExistence(timeout: 10))
        app.buttons["settings.site.more.站点 A"].tap()
        XCTAssertTrue(app.buttons["删除站点和凭据"].waitForExistence(timeout: 5))
        app.buttons["删除站点和凭据"].tap()
        // The confirmation dialog repeats the action as its destructive button.
        XCTAssertTrue(app.buttons["删除站点和凭据"].waitForExistence(timeout: 5))
        app.buttons["删除站点和凭据"].tap()
        XCTAssertTrue(app.buttons["login.submit"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["login.saved.站点 A"].exists)
        XCTAssertFalse(app.tabBars.buttons["概览"].exists)
    }

    @MainActor func testRevokedSessionReturnsToPrefilledLogin() {
        launch(arguments: ["-ui-session-revoked"])
        login(name: "失效站点", url: "https://revoked.example.com")
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(app.staticTexts["login.notice"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["login.notice"].label, "登录已失效，请重新登录")
        XCTAssertEqual(app.textFields["login.url"].value as? String, "https://revoked.example.com")
        // The original sign-in method stays selected (00 §1.7.4).
        XCTAssertTrue(app.textFields["login.email"].exists)
        XCTAssertFalse(app.tabBars.buttons["概览"].exists)
    }

    @MainActor func testBackgroundAndForegroundKeepsSession() {
        launch(arguments: ["-ui-count-user-loads"])
        login(name: "站点 A", url: "https://a.example.com")
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10))
        // The row reads its name first, and the fixture names every user “读取 N 次”; today's spend arrives after the rows.
        let loads = app.buttons["user.1"]
        let settled = NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "读取 ", "今日 $")
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: settled, evaluatedWith: loads)], timeout: 10), .completed, loads.label)
        let before = loads.label
        XCTAssertTrue(before.contains("读取 "), before)
        XCUIDevice.shared.press(.home)
        app.activate()
        // Returning reloads the list (D18): the fixture's read count moves on, and the session is still connected.
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 15))
        let reloaded = NSPredicate(format: "label CONTAINS %@ AND label != %@", "读取 ", before)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation(for: reloaded, evaluatedWith: loads)], timeout: 15), .completed, loads.label)
        XCTAssertFalse(app.buttons["login.submit"].exists)
        app.tabBars.buttons["概览"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.ticker.requests"].firstMatch.waitForExistence(timeout: 15))
    }

    /// D17, now in the detail banner's check (S3-07; the old balance sheet went with S3-08): only the administrator who sent a
    /// pending write may retry its number, and a record without a sender says so.
    @MainActor func testPendingBalanceRetryFollowsTheSender() {
        for (argument, retries, note) in [(nil, true, nil), ("-ui-pending-actor-unknown", true, "无法确认发起人"),
                                          ("-ui-pending-other-actor", false, "只能由同一管理员重试")] as [(String?, Bool, String?)] {
            launch(arguments: ["-ui-pending-money", "-ui-reconcile-notfound"] + (argument.map { [$0] } ?? []))
            login(name: "站点 A", url: "https://a.example.com")
            app.tabBars.buttons["用户"].tap()
            XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10))
            app.buttons["user.1"].tap()
            let check = app.buttons["user.pending.check.0A000000-0000-4000-8000-000000000001"]
            XCTAssertTrue(check.waitForExistence(timeout: 10), app.debugDescription)
            check.tap()
            let alert = app.alerts["服务器上没有这笔记录"]
            XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(alert.buttons["用同一编号重试"].exists, retries, (argument ?? "same sender") + "\n" + app.debugDescription)
            for line in ["无法确认发起人", "只能由同一管理员重试"] {
                let shown = alert.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", line)).firstMatch.exists
                XCTAssertEqual(shown, line == note, line + "\n" + app.debugDescription)
            }
            app.terminate()
        }
    }

    @MainActor private func login(name: String, url: String) {
        XCTAssertTrue(app.textFields["login.name"].waitForExistence(timeout: 10))
        enter(name, in: app.textFields["login.name"], towardBottom: false)
        enter(url, in: app.textFields["login.url"])
        enter("admin@example.com", in: app.textFields["login.email"])
        enter("fixture-password", in: app.secureTextFields["login.password"])
        submitLogin()
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10))
    }

    @MainActor private func submitLogin() {
        // The root page and the 添加站点 sheet have different titles (60 §4.1), and a form scrolled to its top may not have
        // created the button's row yet: any login field shows the page is there.
        let page = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "login.")).firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        // The login form dismisses its keyboard when scrolling. Keep the drag
        // above the keyboard so it scrolls the form rather than typing a key.
        if app.keyboards.firstMatch.exists { scroll(towardBottom: true) }
        reveal(app.buttons["login.submit"])
        app.buttons["login.submit"].tap()
    }

    @MainActor private func enter(_ value: String, in field: XCUIElement, towardBottom: Bool = true) {
        reveal(field, towardBottom: towardBottom)
        field.tap()
        field.typeText(value)
    }

    @MainActor private func reveal(_ element: XCUIElement, towardBottom: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        // SwiftUI List/Form virtualize rows; an offscreen row may not exist in
        // the accessibility tree until scrolling creates it.
        for attempt in 0...8 {
            if element.exists && element.isHittable { return }
            if attempt < 8 { scroll(towardBottom: towardBottom) }
        }
        XCTAssertTrue(element.exists, "Element was not created after bounded scrolling: \(element)", file: file, line: line)
        XCTAssertTrue(element.isHittable, "Element remained offscreen after bounded scrolling: \(element)", file: file, line: line)
    }

    @MainActor private func scroll(towardBottom: Bool) {
        let frame = app.frame
        let navigationBar = app.navigationBars.firstMatch
        let top = max(frame.minY + 100, navigationBar.exists ? navigationBar.frame.maxY + 20 : frame.minY + 100)
        let keyboard = app.keyboards.firstMatch
        let bottom = min(frame.maxY - 100, keyboard.exists ? keyboard.frame.minY - 20 : frame.maxY - 100)
        let height = max(40, bottom - top)
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
        let upper = origin.withOffset(CGVector(dx: 0, dy: top - frame.minY + height * 0.15))
        let lower = origin.withOffset(CGVector(dx: 0, dy: top - frame.minY + height * 0.85))
        (towardBottom ? lower : upper).press(forDuration: 0.05, thenDragTo: towardBottom ? upper : lower)
    }
}
