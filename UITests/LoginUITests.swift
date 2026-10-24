import XCTest

/// 60 §4 against the `-ui-testing` login fixture (DemoLoginGateway): launch arguments shape `settings/public`, email
/// prefixes and codes pick the answers.
final class LoginUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testPasswordLoginShowsConnectedReceipt() {
        launch()
        fillSite(name: "回执验收")
        fillPassword()
        submit()
        assertConnected()
        let receipt = app.staticTexts["receipt.text"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual(receipt.label, "已连接 · 以 admin@example.com 身份操作")
    }

    @MainActor func testLoginMethodNotesAndSatPasteSwitchesToAccessToken() {
        launch()
        fillSite(name: "令牌验收")
        XCTAssertTrue(app.buttons["login.method.password"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["login.method.password"].isSelected)
        XCTAssertFalse(app.staticTexts["login.method.note"].exists)
        tap("login.method.adminKey")
        XCTAssertEqual(app.staticTexts["login.method.note"].label, "以第一个管理员身份操作，不能做需要二次验证的操作。丢失设备请到 Web 重新生成 Key。")
        enter("sat_ui-fixture", in: app.secureTextFields["login.key"])
        XCTAssertTrue(app.buttons["login.method.accessToken"].waitForSelection(), app.debugDescription)
        XCTAssertEqual(app.staticTexts["login.method.note"].label, "以签发它的管理员身份操作，可只读、会过期、能单独吊销。")
        submit()
        assertConnected()
        app.openSitesSettings()
        XCTAssertTrue(app.buttons["settings.site.令牌验收"].label.contains("管理访问令牌"), app.debugDescription)
    }

    @MainActor func testAdminKeyLogin() {
        launch()
        fillSite(name: "密钥验收")
        tap("login.method.adminKey")
        enter("ui-admin-key", in: app.secureTextFields["login.key"])
        submit()
        assertConnected()
        app.openSitesSettings()
        XCTAssertTrue(app.buttons["settings.site.密钥验收"].label.contains("Admin Key"), app.debugDescription)
    }

    @MainActor func testTwoFactorSheetAutoSubmitsAndClearsWrongCode() {
        launch()
        fillSite(name: "两步验收")
        fillPassword(email: "2fa@example.com")
        submit()
        let field = app.textFields["login.totp"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.staticTexts["2***@example.com · 输入身份验证器里的 6 位验证码"].exists, app.debugDescription)
        enter("000000", in: field)
        let error = app.staticTexts["login.totp.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(error.label, "验证码不对，请重新输入")
        XCTAssertNotEqual(field.value as? String, "000000")
        enter("123456", in: field)
        assertConnected()
    }

    @MainActor func testTwoFactorExpiredReturnsToForm() {
        launch()
        fillSite(name: "超时验收")
        fillPassword(email: "2fa@example.com")
        submit()
        let field = app.textFields["login.totp"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
        enter("999999", in: field)
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), app.debugDescription)
        assertError("验证超时，请重新登录")
        XCTAssertFalse(app.tabBars.buttons["概览"].exists)
    }

    @MainActor func testAgreementCheckboxGatesLogin() {
        launch(["-ui-login-agreement-checkbox"])
        fillSite(name: "条款勾选")
        fillPassword()
        submit()
        assertError("请先阅读并同意最新条款后再登录")
        tap("login.agreement")
        XCTAssertTrue(app.buttons["login.agreement"].isSelected)
        XCTAssertTrue(app.buttons["login.agreement"].label.contains("我已阅读并同意《服务条款》"), app.debugDescription)
        submit()
        assertConnected()
    }

    @MainActor func testAgreementModalAppearsOnSubmit() {
        launch(["-ui-login-agreement-modal"])
        fillSite(name: "条款弹窗")
        fillPassword()
        submit()
        let reject = app.buttons["login.agreement.reject"]
        XCTAssertTrue(reject.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["登录条款"].exists)
        reject.tap()
        assertError("请先阅读并同意最新条款后再登录")
        submit()
        let accept = app.buttons["login.agreement.accept"]
        XCTAssertTrue(accept.waitForExistence(timeout: 10), app.debugDescription)
        accept.tap()
        assertConnected()
    }

    @MainActor func testRateLimitedShowsCountdown() {
        launch()
        fillSite(name: "限流验收")
        fillPassword(email: "busy@example.com")
        submit()
        assertError("登录过于频繁，请 3 秒后再试")
        let button = app.buttons["login.submit"]
        XCTAssertTrue(button.label.hasSuffix("秒后重试"), button.label)
        XCTAssertFalse(button.isEnabled)
        let restored = expectation(for: NSPredicate(format: "label == %@ AND enabled == true", "连接站点"), evaluatedWith: button)
        wait(for: [restored], timeout: 8)
    }

    @MainActor func testCaptchaConflictStops() {
        launch(["-ui-login-captcha-conflict"])
        fillSite(name: "冲突验收")
        fillPassword()
        submit()
        assertError("站点同时开启了多个验证码服务，请在 Web 后台修正")
        XCTAssertFalse(app.buttons["captcha.cancel"].exists)
    }

    @MainActor func testCaptchaBridgeShowsHintCancelAndCompletes() {
        launch(["-ui-login-captcha"])
        fillSite(name: "桥页验收")
        fillPassword()
        submit()
        let cancel = app.buttons["captcha.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), app.debugDescription)
        let hint = app.descendants(matching: .any)["captcha.hint"].firstMatch
        XCTAssertTrue(hint.exists, app.debugDescription)
        XCTAssertTrue(hint.label.contains("若页面无法完成验证，请改用 Web 登录或 Admin Key"), hint.label)
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["login.error"].exists)
        submit()
        let complete = app.buttons["captcha.fixture.complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 10), app.debugDescription)
        complete.tap()
        assertConnected()
    }

    @MainActor func testBackendModeHintAppearsAfterAddress() {
        launch(["-ui-login-backend-mode"])
        XCTAssertFalse(app.descendants(matching: .any)["login.backendMode"].firstMatch.exists)
        enter("https://backend-mode.example.invalid", in: app.textFields["login.url"], towardBottom: false)
        let hint = app.descendants(matching: .any)["login.backendMode"].firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(hint.label.contains("站点处于后端模式，仅管理员可登录"), hint.label)
    }

    @MainActor func testEmptyNameUsesPublicSiteName() {
        launch()
        fillSite(name: nil)
        fillPassword()
        submit()
        assertConnected()
        XCTAssertTrue(app.navigationBars["Sub2 演示站"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testEmptyNameWithoutPublicSiteNameIsRejected() {
        launch(["-ui-login-no-site-name"])
        fillSite(name: nil)
        fillPassword()
        submit()
        assertError("请填写站点名称")
    }

    @MainActor func testAddSiteSheetCancels() {
        launch()
        fillSite(name: "原站点")
        fillPassword()
        submit()
        assertConnected()
        app.openSitesSettings()
        app.buttons["settings.add"].tap()
        XCTAssertTrue(app.navigationBars["添加站点"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["login.method.password"].exists)
        let cancel = app.buttons["login.cancel"]
        XCTAssertTrue(cancel.exists, app.debugDescription)
        cancel.tap()
        XCTAssertTrue(app.textFields["login.url"].waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["settings.site.原站点"].exists, app.debugDescription)
    }

    // MARK: - Helpers

    @MainActor private func launch(_ arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["login.submit"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func fillSite(name: String?, url: String = "https://login-ui.example.invalid") {
        enter(url, in: app.textFields["login.url"], towardBottom: false)
        if let name { enter(name, in: app.textFields["login.name"], towardBottom: false) }
    }
    @MainActor private func fillPassword(email: String = "admin@example.com") {
        enter(email, in: app.textFields["login.email"])
        enter("fixture-password", in: app.secureTextFields["login.password"])
    }
    /// Return ends editing, so the keyboard no longer covers the button; a drag over the fields could open their edit menu.
    @MainActor private func submit() {
        if app.keyboards.firstMatch.exists {
            app.typeText("\n")
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        }
        tap("login.submit")
    }
    @MainActor private func tap(_ identifier: String) {
        let button = app.buttons[identifier]
        reveal(button)
        button.tap()
    }
    @MainActor private func assertConnected(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
    }
    @MainActor private func assertError(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let error = app.staticTexts["login.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        XCTAssertEqual(error.label, text, file: file, line: line)
    }
    @MainActor private func enter(_ value: String, in field: XCUIElement, towardBottom: Bool = true) {
        reveal(field, towardBottom: towardBottom)
        field.tap()
        field.typeText(value)
    }
    @MainActor private func reveal(_ element: XCUIElement, towardBottom: Bool = true, file: StaticString = #filePath, line: UInt = #line) {
        for attempt in 0...8 {
            if element.exists && element.isHittable { return }
            if attempt < 8 { scroll(towardBottom: towardBottom) }
        }
        XCTAssertTrue(element.isHittable, "Element remained offscreen after bounded scrolling: \(element)", file: file, line: line)
    }
    /// Drags above the keyboard so the form scrolls instead of typing a key.
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

private extension XCUIElement {
    /// The method row changes selection right after the pasted key's last character.
    @MainActor func waitForSelection(timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isSelected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return isSelected
    }
}
