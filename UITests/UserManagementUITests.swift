import XCTest

final class UserManagementUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testCreateThenEditUserFieldsAndLeavePasswordUnchanged() {
        launchAndLogin()
        defer { diagnostics("users-create-edit-final") }
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10))
        app.buttons["users.create"].tap()
        set("created@example.invalid", field: "user-editor.email", towardBottom: false)
        set("新建用户", field: "user-editor.username")
        set("fixture-create-password", field: "user-editor.password")
        chooseRole("供应商")
        set("创建备注", field: "user-editor.notes")
        set("3", field: "user-editor.concurrency")
        set("60", field: "user-editor.rpm")
        set("12.50", field: "user-editor.initial-balance")
        confirmWrite(email: "created@example.invalid")
        // The fixture holds 26 users (S3-02); the new one is 27 and the newest, so it is the list's first row.
        XCTAssertTrue(app.buttons["user.27"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["user.27"].tap()
        openEditor()
        assertField("user-editor.email", equals: "created@example.invalid")
        assertField("user-editor.username", equals: "新建用户")
        set("edited@example.invalid", field: "user-editor.email", towardBottom: false)
        set("编辑用户名", field: "user-editor.username")
        // A nonempty new password follows validation; fixture never persists or displays it.
        set("fixture-new-password", field: "user-editor.password")
        chooseRole("管理员")
        set("编辑备注", field: "user-editor.notes")
        set("0", field: "user-editor.concurrency")
        set("45", field: "user-editor.rpm")
        set("测试调整并发", field: "user-editor.adjustment-notes")
        confirmWrite(email: "edited@example.invalid")
        reveal(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "edited@example.invalid")).firstMatch, towardBottom: false)
        openEditor()
        assertField("user-editor.email", equals: "edited@example.invalid")
        assertField("user-editor.username", equals: "编辑用户名")
        assertField("user-editor.notes", equals: "编辑备注")
        assertField("user-editor.concurrency", equals: "0")
        assertField("user-editor.rpm", equals: "45")
        reveal(app.buttons["user-editor.role"], towardBottom: false)
        XCTAssertTrue(app.buttons["user-editor.role"].label.contains("管理员"), app.debugDescription)
        // Reopening clears the password; a later name-only edit must succeed without supplying it.
        let password = element("user-editor.password")
        reveal(password, towardBottom: false)
        let secureValue = password.value as? String ?? ""
        XCTAssertFalse(secureValue.contains("•") || secureValue.contains("fixture-new-password"))
        set("仅修改名称", field: "user-editor.username", towardBottom: false)
        confirmWrite(email: "edited@example.invalid")
        reveal(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "仅修改名称")).firstMatch, towardBottom: false)
        XCTAssertFalse(app.staticTexts["fixture-create-password"].exists)
        XCTAssertFalse(app.staticTexts["fixture-new-password"].exists)
    }

    @MainActor func testCreateValidationAndEditPasswordValidation() {
        launchAndLogin()
        defer { diagnostics("users-validation-final") }
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10))
        app.buttons["users.create"].tap()
        prepareWrite()
        reveal(element("user-editor.result"))
        XCTAssertTrue(element("user-editor.result").waitForExistence(timeout: 5))
        XCTAssertTrue(element("user-editor.result").label.contains("邮箱"), app.debugDescription)
        set("validation@example.invalid", field: "user-editor.email", towardBottom: false)
        prepareWrite()
        reveal(element("user-editor.result"))
        XCTAssertTrue(element("user-editor.result").label.contains("密码"), app.debugDescription)
        app.buttons["user-editor.close"].tap()
        app.buttons["user.1"].tap()
        openEditor()
        set("short", field: "user-editor.password", towardBottom: false)
        prepareWrite()
        reveal(element("user-editor.result"))
        XCTAssertTrue(element("user-editor.result").waitForExistence(timeout: 5))
        XCTAssertTrue(element("user-editor.result").label.contains("密码"), app.debugDescription)
        set("valid-password", field: "user-editor.password", towardBottom: false)
        confirmWrite(email: "alice@example.com")
        XCTAssertTrue(app.buttons["user.edit"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor private func launchAndLogin() {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        set("用户管理验收", field: "login.name", towardBottom: false)
        set("https://users-ui.example.invalid", field: "login.url")
        set("admin@example.com", field: "login.email")
        set("fixture-password", field: "login.password")
        reveal(app.buttons["login.submit"]); app.buttons["login.submit"].tap()
        XCTAssertTrue(app.tabBars.buttons["用户"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func openEditor() {
        reveal(app.buttons["user.edit"]); app.buttons["user.edit"].tap()
        XCTAssertTrue(element("user-editor.email").waitForExistence(timeout: 5), app.debugDescription)
    }
    @MainActor private func chooseRole(_ title: String) {
        reveal(app.buttons["user-editor.role"])
        app.buttons["user-editor.role"].tap()
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 3), app.debugDescription)
        app.buttons[title].tap()
    }
    @MainActor private func prepareWrite() {
        reveal(app.buttons["user-editor.prepare"]); app.buttons["user-editor.prepare"].tap()
    }
    @MainActor private func confirmWrite(email: String) {
        prepareWrite()
        XCTAssertTrue(app.buttons["确认发送"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", email)).firstMatch.exists, app.debugDescription)
        app.buttons["确认发送"].tap()
        // A save closes the editor. Scrolling while it slides out measures its bar, and the clamped drag taps the bottom
        // edge of the detail, where S3-04's “充值与调整记录” row now sits.
        XCTAssertTrue(element("user-editor.email").waitForNonExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func assertField(_ identifier: String, equals value: String) {
        let field = element(identifier); reveal(field)
        XCTAssertEqual(field.value as? String, value, app.debugDescription)
    }
    @MainActor private func set(_ value: String, field identifier: String, towardBottom: Bool = true) {
        let field = element(identifier); reveal(field, towardBottom: towardBottom); field.tap()
        let current = field.value as? String ?? ""
        if !current.isEmpty && current != field.placeholderValue {
            // A multiline field's default activation point can place the caret
            // before its text. Tap its trailing last line before backspacing.
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            let cleared = field.value as? String ?? ""
            let isCleared = cleared.isEmpty || cleared == field.placeholderValue
            if !isCleared { diagnostics("users-clear-field-\(identifier)-failure") }
            XCTAssertTrue(isCleared, "Field \(identifier) must be empty before replacement.\n\(app.debugDescription)")
            guard isCleared else { return }
        }
        field.typeText(value)
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func reveal(_ element: XCUIElement, towardBottom: Bool = true) {
        for attempt in 0...10 {
            if element.exists && element.isHittable { return }
            if attempt < 10 { scroll(towardBottom: towardBottom) }
        }
        diagnostics("users-reveal-failure")
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }
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
