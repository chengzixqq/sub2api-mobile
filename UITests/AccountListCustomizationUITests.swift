import XCTest

final class AccountListCustomizationUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testAccountGroupsConcurrencyAndFieldOrderPersistAcrossTabs() {
        launch()
        defer { diagnostics("account-fields-persist-across-tabs") }
        login(name: "账号字段验收", email: "fields@example.com")
        showAccounts()
        assertFields(groups: true, concurrency: true)

        openEditor()
        setField("groups", enabled: false)
        setField("concurrency", enabled: false)
        finishEditor()
        assertFields(groups: false, concurrency: false)

        openEditor()
        setField("groups", enabled: true)
        setField("concurrency", enabled: true)
        // A button alternative also makes reordering available without a drag.
        app.buttons["list-fields.accounts.groups.up"].tap()
        app.buttons["list-fields.accounts.groups.up"].tap()
        let groups = app.switches["list-fields.accounts.groups"]
        let platform = app.switches["list-fields.accounts.platform"]
        XCTAssertLessThan(groups.frame.minY, platform.frame.minY)
        XCTAssertFalse(app.buttons["list-fields.accounts.groups.up"].isEnabled)
        finishEditor()
        assertFields(groups: true, concurrency: true)
        assertGroupsPrecedePlatform()
        diagnostics("account-groups-concurrency-inline-and-reordered")

        app.tabBars.buttons["用户"].tap()
        app.tabBars.buttons["账号"].tap()
        assertFields(groups: true, concurrency: true)
        assertGroupsPrecedePlatform()
        openEditor()
        XCTAssertLessThan(app.switches["list-fields.accounts.groups"].frame.minY,
                          app.switches["list-fields.accounts.platform"].frame.minY)
        finishEditor()
    }

    @MainActor func testAccountFieldPreferencesAreIsolatedBetweenSameSiteIdentities() {
        launch()
        defer { diagnostics("account-fields-same-site-identity-isolation") }
        login(name: "字段管理员 A", email: "a@example.com")
        showAccounts()
        openEditor()
        setField("groups", enabled: false)
        setField("concurrency", enabled: false)
        finishEditor()
        assertFields(groups: false, concurrency: false)

        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.add"].tap()
        // The same HTTPS origin with a new login must receive its own defaults.
        login(name: "字段管理员 B", email: "b@example.com")
        showAccounts()
        assertFields(groups: true, concurrency: true)
        diagnostics("account-fields-identity-b-defaults")

        switchIdentity("字段管理员 A")
        showAccounts()
        assertFields(groups: false, concurrency: false)
        openEditor()
        XCTAssertEqual(app.switches["list-fields.accounts.groups"].value as? String, "0")
        XCTAssertEqual(app.switches["list-fields.accounts.concurrency"].value as? String, "0")
        finishEditor()

        switchIdentity("字段管理员 B")
        showAccounts()
        assertFields(groups: true, concurrency: true)
    }

    @MainActor private func launch() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    @MainActor private func login(name: String, email: String) {
        XCTAssertTrue(app.textFields["login.name"].waitForExistence(timeout: 10))
        enter(name, in: app.textFields["login.name"], towardBottom: false)
        enter("https://account-fields.example.com", in: app.textFields["login.url"])
        enter(email, in: app.textFields["login.email"])
        enter("fixture-password", in: app.secureTextFields["login.password"])
        if app.keyboards.firstMatch.exists { scroll(towardBottom: true) }
        reveal(app.buttons["login.submit"])
        app.buttons["login.submit"].tap()
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10))
    }

    @MainActor private func showAccounts() {
        app.tabBars.buttons["账号"].tap()
        XCTAssertTrue(app.buttons["account.1"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor private func openEditor() {
        let button = app.buttons["accounts.fields"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(app.switches["list-fields.accounts.groups"].waitForExistence(timeout: 5))
    }

    @MainActor private func setField(_ name: String, enabled: Bool) {
        let toggle = app.switches["list-fields.accounts.\(name)"]
        reveal(toggle)
        let expected = enabled ? "1" : "0"
        print("LIST_FIELD_BEFORE \(name) expected=\(expected) value=\(String(describing: toggle.value)) frame=\(toggle.frame)")
        print(app.debugDescription)
        diagnostics("account-field-\(name)-before-\(expected)")
        if (toggle.value as? String == "1") != enabled {
            // Target the trailing switch track explicitly. A Toggle's AX bounds
            // can also include its title, whose midpoint need not toggle it.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                .withOffset(CGVector(dx: -20, dy: 0)).tap()
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: toggle)
        let result = XCTWaiter.wait(for: [changed], timeout: 3)
        print("LIST_FIELD_AFTER \(name) expected=\(expected) value=\(String(describing: toggle.value)) frame=\(toggle.frame)")
        print(app.debugDescription)
        // Keep evidence before a failed assertion; XCTest can stop before defer.
        diagnostics("account-field-\(name)-after-\(expected)")
        XCTAssertEqual(result, .completed, "The rendered field switch did not change value.")
        XCTAssertEqual(toggle.value as? String, expected)
    }

    @MainActor private func finishEditor() {
        app.buttons["list-fields.accounts.done"].tap()
        XCTAssertTrue(app.buttons["accounts.fields"].waitForExistence(timeout: 5))
    }

    @MainActor private func assertFields(groups: Bool, concurrency: Bool,
                                        file: StaticString = #filePath, line: UInt = #line) {
        let row = app.buttons["account.1"]
        reveal(row, towardBottom: false)
        // NavigationLink combines row text for VoiceOver on some iOS versions.
        // Inspect its actual label as well as exposed child text, never a fixture
        // stored outside the rendered account row.
        let text = row.label + " " + row.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertEqual(text.contains("分组："), groups, text, file: file, line: line)
        XCTAssertEqual(text.contains("并发："), concurrency, text, file: file, line: line)
        if groups {
            XCTAssertTrue(text.contains("标准分组"), text, file: file, line: line)
            XCTAssertTrue(text.contains("高级分组"), text, file: file, line: line)
        }
        if concurrency { XCTAssertTrue(text.contains("并发：4"), text, file: file, line: line) }
    }

    @MainActor private func assertGroupsPrecedePlatform(file: StaticString = #filePath, line: UInt = #line) {
        let row = app.buttons["account.1"]
        let group = row.descendants(matching: .any)["account.1.field.groups"].firstMatch
        let platform = row.descendants(matching: .any)["account.1.field.platform"].firstMatch
        if group.exists && platform.exists {
            let isBefore = group.frame.minY < platform.frame.minY ||
                (abs(group.frame.minY - platform.frame.minY) < 1 && group.frame.minX < platform.frame.minX)
            XCTAssertTrue(isBefore, row.debugDescription, file: file, line: line)
        } else {
            let text = row.label
            guard let groupRange = text.range(of: "分组："), let platformRange = text.range(of: "平台：") else {
                XCTFail("Rendered row has no field order: \(row.debugDescription)", file: file, line: line)
                return
            }
            XCTAssertLessThan(groupRange.lowerBound, platformRange.lowerBound, text, file: file, line: line)
        }
    }

    @MainActor private func switchIdentity(_ name: String) {
        app.tabBars.buttons["设置"].tap()
        let button = app.buttons["settings.site.\(name)"]
        reveal(button, towardBottom: false)
        button.tap()
        app.tabBars.buttons["概览"].tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor private func enter(_ text: String, in field: XCUIElement, towardBottom: Bool = true) {
        reveal(field, towardBottom: towardBottom)
        field.tap()
        field.typeText(text)
    }

    @MainActor private func reveal(_ element: XCUIElement, towardBottom: Bool = true,
                                   file: StaticString = #filePath, line: UInt = #line) {
        for attempt in 0...8 {
            if element.exists && element.isHittable { return }
            if attempt < 8 { scroll(towardBottom: towardBottom) }
        }
        XCTAssertTrue(element.exists, "Element missing after scrolling: \(element)", file: file, line: line)
        XCTAssertTrue(element.isHittable, "Element is offscreen: \(element)", file: file, line: line)
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

    @MainActor private func diagnostics(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + "-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
