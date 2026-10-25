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

        app.openSitesSettings()
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

    @MainActor func testAccountRuntimeUsesOccupancyAndSeparatesUserChargeFromCost() {
        launch()
        defer { diagnostics("account-runtime-and-billing") }
        login(name: "账号容量验收", email: "runtime@example.com")
        showAccounts()
        assertRowContains("在用并发：2")
        assertRowContains("在用 RPM：37")
        XCTAssertFalse(rowText().contains("在用并发：4"), rowText())
        XCTAssertFalse(rowText().contains("在用 RPM：60"), rowText())
        diagnostics("account-runtime-current-values-on-list")

        openAccountDetail()
        assertDetail("capacity", contains: "并发 2 / 4")
        assertDetail("concurrency", contains: "2")
        assertDetail("rpm", contains: "37")
        assertDetail("user-cost", contains: "$0.31")
        assertDetail("cost", contains: "$0.12")
        XCTAssertFalse(element("account.detail.user-cost").label.contains("$0.12"))
        XCTAssertFalse(element("account.detail.cost").label.contains("$0.31"))
        diagnostics("account-detail-distinct-charge-and-cost")
    }

    @MainActor func testCapacityAndNewFieldsCanBeHiddenReorderedAndRestoredAcrossTabs() {
        launch()
        defer { diagnostics("account-capacity-field-customization") }
        login(name: "容量字段验收", email: "capacity-fields@example.com")
        showAccounts()
        openEditor()
        setField("rpm", enabled: false)
        setField("capacity", enabled: false)
        setField("todayStats", enabled: false)
        finishEditor()
        XCTAssertFalse(rowText().contains("容量："), rowText())
        XCTAssertFalse(rowText().contains("在用 RPM："), rowText())
        XCTAssertFalse(rowText().contains("今日统计："), rowText())

        openEditor()
        setField("rpm", enabled: true)
        setField("accountID", enabled: true)
        setField("capacity", enabled: true)
        setField("todayStats", enabled: true)
        setField("baseRPM", enabled: true)
        moveFieldToFirst("capacity")
        finishEditor()
        assertRowContains("容量：")
        assertRowContains("在用 RPM：37")
        assertRowContains("账号 ID：1")
        assertRowContains("基础 RPM 限额：60")
        assertRowContains("$0.31")
        assertRowContains("$0.12")
        assertCapacityPrecedesPlatform()
        diagnostics("account-capacity-and-today-stats-reordered")

        app.tabBars.buttons["用户"].tap()
        showAccounts()
        assertRowContains("容量：")
        assertRowContains("在用 RPM：37")
        assertRowContains("今日统计：")
        assertCapacityPrecedesPlatform()
        openEditor()
        for field in ["capacity", "rpm", "accountID", "todayStats", "baseRPM"] {
            let toggle = app.switches["list-fields.accounts.\(field)"]
            reveal(toggle)
            XCTAssertEqual(toggle.value as? String, "1", field)
        }
        reveal(app.buttons["list-fields.accounts.capacity.up"], towardBottom: false)
        XCTAssertFalse(app.buttons["list-fields.accounts.capacity.up"].isEnabled)
        finishEditor()
    }

    @MainActor func testMissingRuntimeRPMStaysUnavailableDespiteConfiguredLimit() {
        launch(arguments: ["-ui-account-runtime-missing"])
        defer { diagnostics("account-runtime-missing-rpm") }
        login(name: "缺失占用验收", email: "missing-rpm@example.com")
        showAccounts()
        assertRowContains("在用并发：2")
        assertRowContains("在用 RPM：—")
        XCTAssertFalse(rowText().contains("在用 RPM：0"), rowText())
        XCTAssertFalse(rowText().contains("在用 RPM：60"), rowText())
        diagnostics("account-list-missing-rpm-unavailable")
        openAccountDetail()
        assertDetail("rpm", contains: "—")
        let rpm = element("account.detail.rpm").label
        XCTAssertFalse(rpm.contains("60"), rpm)
        XCTAssertFalse(rpm.contains("0"), rpm)
        assertDetail("concurrency", contains: "2", towardBottom: false)
    }

    @MainActor func testTodayStatsFailureDoesNotBlockListOrDetailRuntime() {
        launch(arguments: ["-ui-account-stats-error"])
        defer { diagnostics("account-stats-failure-keeps-runtime") }
        login(name: "统计隔离验收", email: "stats-error@example.com")
        showAccounts()
        openEditor()
        setField("todayStats", enabled: true)
        finishEditor()
        let batchError = element("accounts.today-stats.error")
        reveal(batchError)
        XCTAssertTrue(batchError.label.contains("账号今日统计测试失败"), batchError.label)
        reveal(app.buttons["account.1"], towardBottom: false)
        assertRowContains("在用并发：2")
        assertRowContains("在用 RPM：37")
        diagnostics("account-batch-stats-error-keeps-list-runtime")
        openAccountDetail()
        assertDetail("concurrency", contains: "2")
        assertDetail("rpm", contains: "37")
        let detailError = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "账号今日统计测试失败")).firstMatch
        reveal(detailError)
        XCTAssertTrue(detailError.exists)
        XCTAssertFalse(element("account.detail.user-cost").exists)
        XCTAssertFalse(element("account.detail.cost").exists)
    }

    @MainActor func testSlowTodayStatsAllowsIndependentRuntimeRefresh() {
        launch(arguments: ["-ui-account-slow-stats"])
        defer { diagnostics("account-slow-stats-independent-runtime") }
        login(name: "慢统计验收", email: "stats-slow@example.com")
        showAccounts()
        openAccountDetail()
        assertDetail("concurrency", contains: "2")
        assertDetail("rpm", contains: "37")
        let updated = element("account.detail.runtime-updated")
        reveal(updated)
        XCTAssertTrue(updated.waitForExistence(timeout: 5), app.debugDescription)
        let refresh = app.buttons["account.detail.reload-runtime"]
        reveal(refresh)
        XCTAssertTrue(refresh.isEnabled)
        let previousUpdate = updated.label
        refresh.tap()
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: refresh)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 5), .completed)
        let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", previousUpdate), object: updated)
        XCTAssertEqual(XCTWaiter.wait(for: [refreshed], timeout: 5), .completed)
        diagnostics("account-runtime-refreshed-while-today-pending")
        let pending = element("account.detail.stats-loading")
        reveal(pending)
        XCTAssertTrue(pending.exists, app.debugDescription)
        XCTAssertFalse(element("account.detail.user-cost").exists)
        XCTAssertFalse(element("account.detail.cost").exists)
    }

    @MainActor private func launch(arguments: [String] = []) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
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
        toggle.waitUntilSettled()
        let expected = enabled ? "1" : "0"
        if (toggle.value as? String == "1") != enabled {
            // Target the trailing switch track explicitly. A Toggle's AX bounds
            // can also include its title, whose midpoint need not toggle it.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                .withOffset(CGVector(dx: -20, dy: 0)).tap()
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: toggle)
        let result = XCTWaiter.wait(for: [changed], timeout: 3)
        // Evidence only for a failure (XCTest can stop before defer): every full snapshot costs seconds on a busy Mac.
        if result != .completed { diagnostics("account-field-\(name)-after-\(expected)") }
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
        XCTAssertEqual(text.contains("在用并发："), concurrency, text, file: file, line: line)
        if groups {
            XCTAssertTrue(text.contains("标准分组"), text, file: file, line: line)
            XCTAssertTrue(text.contains("高级分组"), text, file: file, line: line)
        }
        if concurrency { XCTAssertTrue(text.contains("在用并发：2"), text, file: file, line: line) }
    }

    @MainActor private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor private func rowText() -> String {
        let row = app.buttons["account.1"]
        return row.label + " " + row.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " ")
    }

    @MainActor private func assertRowContains(_ expected: String,
                                             file: StaticString = #filePath, line: UInt = #line) {
        let rendered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", expected),
                                                 object: app.buttons["account.1"])
        XCTAssertEqual(XCTWaiter.wait(for: [rendered], timeout: 10), .completed, rowText(), file: file, line: line)
    }

    @MainActor private func openAccountDetail() {
        let row = app.buttons["account.1"]
        reveal(row, towardBottom: false)
        row.tap()
        XCTAssertTrue(element("account.detail.capacity").waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor private func assertDetail(_ field: String, contains expected: String, towardBottom: Bool = true,
                                        file: StaticString = #filePath, line: UInt = #line) {
        let value = element("account.detail.\(field)")
        reveal(value, towardBottom: towardBottom)
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", expected), object: value)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 10), .completed, value.label, file: file, line: line)
    }

    @MainActor private func moveFieldToFirst(_ name: String) {
        for _ in 0..<60 {
            let up = app.buttons["list-fields.accounts.\(name).up"]
            reveal(up, towardBottom: false)
            up.waitUntilSettled()
            if !up.isEnabled { return }
            // A reordered row may keep its AX element while moving behind the
            // sheet's navigation bar. isHittable alone can still accept it.
            let top = app.navigationBars["账号列表字段"].frame.maxY + 8
            let bottom = app.frame.maxY - 40
            if up.frame.minY < top {
                scroll(towardBottom: false)
                continue
            }
            if up.frame.maxY > bottom {
                scroll(towardBottom: true)
                continue
            }
            let frame = up.frame
            // XCTest's element tap used a stale synthesized hit point after
            // repeated reorders. Use the observed, visible control center.
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: frame.midX - app.frame.minX,
                dy: frame.midY - app.frame.minY)).tap()
            let moved = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in
                guard let button = object as? XCUIElement else { return false }
                return !button.isEnabled || button.frame != frame
            }, object: up)
            if XCTWaiter.wait(for: [moved], timeout: 3) != .completed {
                diagnostics("account-field-\(name)-move-no-change")
                XCTFail("Field did not move after tapping its visible center: \(name)")
                return
            }
        }
        diagnostics("account-field-\(name)-move-stalled")
        XCTFail("Field did not reach the first position: \(name)")
    }

    @MainActor private func assertCapacityPrecedesPlatform(file: StaticString = #filePath, line: UInt = #line) {
        let text = rowText()
        guard let capacity = text.range(of: "容量："), let platform = text.range(of: "平台：") else {
            XCTFail("Missing capacity/platform in rendered row: \(text)", file: file, line: line)
            return
        }
        XCTAssertLessThan(capacity.lowerBound, platform.lowerBound, text, file: file, line: line)
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
        app.openSitesSettings()
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
