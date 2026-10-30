import XCTest

/// S0-13: the global compliance and step-up sheets over the fixtures of `-ui-compliance-required`, `-ui-step-up-required`
/// and `-ui-step-up-no-totp` (DemoData, AppModel+Security.swift).
final class SecurityPromptUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testComplianceRequiredAfterLoginNeedsExactPhrase() {
        launchAndLogin("-ui-compliance-required")
        defer { diagnostics("compliance-final") }
        XCTAssertTrue(element("compliance.sheet").waitForExistence(timeout: 10), app.debugDescription)
        let confirm = app.buttons["compliance.confirm"]
        XCTAssertTrue(confirm.exists); XCTAssertFalse(confirm.isEnabled)
        let phrase = element("compliance.phrase")
        phrase.tap()
        phrase.typeText("我已阅读、理解并同意 Sub2API 部署与运营合规")
        XCTAssertFalse(confirm.isEnabled, "少两个字时不能确认")
        phrase.typeText("承诺")
        XCTAssertTrue(waitUntil(confirm, "isEnabled == true"), app.debugDescription)
        diagnostics("compliance-sheet")
        confirm.tap()
        XCTAssertTrue(element("compliance.sheet").waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.tabBars.buttons["概览"].isHittable)
    }

    @MainActor func testStepUpReturnsToConfirmationWithSameRequest() {
        launchAndLogin("-ui-step-up-required")
        defer { diagnostics("step-up-final") }
        makeFirstUserAdministrator()
        let code = element("stepup.code")
        XCTAssertTrue(code.waitForExistence(timeout: 10), app.debugDescription)
        code.tap()
        code.typeText("000000")
        let error = element("stepup.error")
        XCTAssertTrue(error.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(error.label, "验证码不对，请重新输入")
        diagnostics("step-up-sheet-error")
        XCTAssertFalse((code.value as? String ?? "").contains("0"), "错误后应清空输入")
        code.typeText("123456")
        XCTAssertTrue(code.waitForNonExistence(timeout: 10), app.debugDescription)
        // S3-11: verified, the edit page asks once more, then saves and returns to the detail.
        let confirm = app.alerts["把「Alice」设为管理员？"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(confirm.staticTexts["二次验证已通过。管理员可以管理全部账号、用户和资金。\n同时保存：角色"].exists, app.debugDescription)
        confirm.buttons["设为管理员并保存"].tap()
        XCTAssertTrue(element("user-edit.email").waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Alice"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testStepUpWithoutTOTPShowsNoticeOnly() {
        launchAndLogin("-ui-step-up-no-totp")
        defer { diagnostics("step-up-no-totp-final") }
        makeFirstUserAdministrator()
        XCTAssertTrue(app.staticTexts["需要先在 Web 端开启二次验证"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(element("stepup.code").exists)
        diagnostics("step-up-no-totp-notice")
        app.buttons["stepup.ack"].tap()
        // S3-11: the edit page stays with its change, and “保存” can be pressed again.
        XCTAssertTrue(element("stepup.ack").waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(element("user-edit.role").exists, app.debugDescription)
        XCTAssertTrue(waitUntil(app.buttons["user-edit.save"], "isEnabled == true"), app.debugDescription)
    }

    @MainActor private func launchAndLogin(_ argument: String) {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing", argument]; app.launchQuietly()
        type("安全验收", into: "login.name")
        type("https://security-ui.example.invalid", into: "login.url")
        type("admin@example.com", into: "login.email")
        type("fixture-password", into: "login.password")
        reveal(app.buttons["login.submit"]); app.buttons["login.submit"].tap()
        XCTAssertTrue(app.tabBars.buttons["用户"].waitForExistence(timeout: 10), app.debugDescription)
    }
    /// Opens the first fixture user's edit page (S3-11), makes it an administrator and presses “保存”, which asks for step-up.
    @MainActor private func makeFirstUserAdministrator() {
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["user.1"].tap()
        // S3-05: 编辑用户 is in the detail's ⋯ menu, whose items are found by their words.
        XCTAssertTrue(app.buttons["user.more"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["user.more"].tap()
        XCTAssertTrue(app.buttons["编辑用户"].waitForExistence(timeout: 3), app.debugDescription)
        app.buttons["编辑用户"].tap()
        XCTAssertTrue(element("user-edit.email").waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["user-edit.segment.access"].tap()
        let role = app.segmentedControls["user-edit.role"]
        XCTAssertTrue(role.waitForExistence(timeout: 5), app.debugDescription)
        role.buttons["管理员"].tap()
        app.buttons["user-edit.save"].tap()
    }
    @MainActor private func type(_ value: String, into identifier: String) {
        let field = element(identifier); reveal(field, towardBottom: false); field.tap(); field.typeText(value)
    }
    @MainActor private func waitUntil(_ element: XCUIElement, _ format: String) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)], timeout: 5) == .completed
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func reveal(_ element: XCUIElement, towardBottom: Bool = true) {
        for attempt in 0...10 {
            if element.exists && element.isHittable { return }
            if attempt < 10 { scroll(towardBottom: towardBottom) }
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }
    /// Drags inside the visible content, above the keyboard when it is up.
    @MainActor private func scroll(towardBottom: Bool) {
        let frame = app.frame
        let top = max(frame.minY + 100, app.navigationBars.firstMatch.frame.maxY + 20)
        let keyboard = app.keyboards.firstMatch
        let bottom = min(frame.maxY - 100, keyboard.exists ? keyboard.frame.minY - 20 : frame.maxY - 100)
        let height = max(40, bottom - top)
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
        let upper = origin.withOffset(CGVector(dx: 0, dy: top - frame.minY + height * 0.15))
        let lower = origin.withOffset(CGVector(dx: 0, dy: top - frame.minY + height * 0.85))
        (towardBottom ? lower : upper).press(forDuration: 0.05, thenDragTo: towardBottom ? upper : lower)
    }
    @MainActor private func diagnostics(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = name + "-accessibility"; hierarchy.lifetime = .keepAlways; add(hierarchy)
    }
}
