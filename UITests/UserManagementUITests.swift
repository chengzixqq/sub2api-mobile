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
        chooseRole("代运营")
        set("创建备注", field: "user-editor.notes")
        set("3", field: "user-editor.concurrency")
        set("60", field: "user-editor.rpm")
        set("12.50", field: "user-editor.initial-balance")
        confirmWrite(email: "created@example.invalid")
        XCTAssertTrue(app.buttons["user.3"].waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["user.3"].tap()
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

    @MainActor func testUserFieldSelectionAndOrderRemainAfterReopening() {
        launchAndLogin()
        defer { diagnostics("users-fields-final") }
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10))
        app.buttons["users.fields"].tap()
        reveal(app.buttons["list-fields.users.reset"])
        app.buttons["list-fields.users.reset"].tap()
        setField("createdAt", enabled: true, towardBottom: false)
        setField("notes", enabled: true)
        let moveDown = app.buttons["list-fields.users.username.down"]
        reveal(moveDown, towardBottom: false)
        moveDown.tap()
        app.buttons["完成"].tap()
        let username = element("user.1.field.username"), role = element("user.1.field.role")
        XCTAssertTrue(username.waitForExistence(timeout: 5) && role.exists, app.debugDescription)
        XCTAssertTrue(role.frame.minY < username.frame.minY || (abs(role.frame.minY - username.frame.minY) < 1 && role.frame.minX < username.frame.minX), "Moved role should precede username")
        XCTAssertTrue(element("user.1.field.createdAt").exists)
        XCTAssertTrue(element("user.1.field.notes").label.contains("常用测试用户"))
        app.tabBars.buttons["账号"].tap()
        app.tabBars.buttons["用户"].tap()
        app.buttons["users.fields"].tap()
        reveal(app.switches["list-fields.users.createdAt"])
        XCTAssertEqual(app.switches["list-fields.users.createdAt"].value as? String, "1")
        reveal(app.switches["list-fields.users.notes"])
        XCTAssertEqual(app.switches["list-fields.users.notes"].value as? String, "1")
        app.buttons["完成"].tap()
        XCTAssertTrue(role.frame.minY < username.frame.minY || (abs(role.frame.minY - username.frame.minY) < 1 && role.frame.minX < username.frame.minX))
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
    }
    @MainActor private func assertField(_ identifier: String, equals value: String) {
        let field = element(identifier); reveal(field)
        XCTAssertEqual(field.value as? String, value, app.debugDescription)
    }
    @MainActor private func setField(_ name: String, enabled: Bool, towardBottom: Bool = true) {
        let toggle = app.switches["list-fields.users.\(name)"]
        reveal(toggle, towardBottom: towardBottom)
        let expected = enabled ? "1" : "0"
        print("USER_LIST_FIELD_BEFORE \(name) expected=\(expected) value=\(String(describing: toggle.value)) frame=\(toggle.frame)")
        print(app.debugDescription)
        diagnostics("user-field-\(name)-before-\(expected)")
        if (toggle.value as? String == "1") != enabled {
            // The switch's AX bounds include its title; tap the trailing track.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                .withOffset(CGVector(dx: -20, dy: 0)).tap()
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: toggle)
        let result = XCTWaiter.wait(for: [changed], timeout: 3)
        print("USER_LIST_FIELD_AFTER \(name) expected=\(expected) value=\(String(describing: toggle.value)) frame=\(toggle.frame)")
        print(app.debugDescription)
        diagnostics("user-field-\(name)-after-\(expected)")
        XCTAssertEqual(result, .completed, "The rendered user field switch did not change value.")
        XCTAssertEqual(toggle.value as? String, expected)
    }
    @MainActor private func set(_ value: String, field identifier: String, towardBottom: Bool = true) {
        let field = element(identifier); reveal(field, towardBottom: towardBottom); field.tap()
        let current = field.value as? String ?? ""
        if !current.isEmpty && current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
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
