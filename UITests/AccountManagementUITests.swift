import XCTest

final class AccountManagementUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!
    @MainActor func testAuthenticationFilterAndForegroundRefreshToggle() {
        launchAndLogin()
        defer { capture("account-filter-final") }
        app.tabBars.buttons["账号"].tap()
        XCTAssertTrue(app.buttons["account.1"].waitForExistence(timeout: 10))
        let refresh = app.switches["accounts.auto-refresh"]
        XCTAssertEqual(refresh.value as? String, "0")
        refresh.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -20, dy: 0)).tap()
        XCTAssertEqual(refresh.value as? String, "1")
        app.buttons["accounts.filters"].tap()
        let type = element("accounts.type")
        XCTAssertTrue(type.waitForExistence(timeout: 5)); type.tap()
        app.buttons["OAuth"].tap()
        app.buttons["accounts.filters.done"].tap()
        XCTAssertTrue(app.buttons["account.2"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["account.1"].exists)
        capture("account-filter-oauth")
    }
    @MainActor func testQuickEditConfirmsTargetAndPreservesChangedMetadata() {
        launchAndLogin()
        defer { capture("account-edit-final") }
        app.tabBars.buttons["账号"].tap()
        XCTAssertTrue(app.buttons["account.1"].waitForExistence(timeout: 10))
        app.buttons["account.1"].tap()
        let edit = app.buttons["account.edit"]; reveal(edit); edit.tap()
        let name = app.textFields["account.edit.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10)); name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "测试上游 A".count) + "编辑后的账号")
        app.buttons["account.edit.save"].tap()
        XCTAssertTrue(app.buttons["确认保存"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "账号管理验收")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["确认保存"].tap()
        XCTAssertTrue(app.navigationBars["编辑后的账号"].waitForExistence(timeout: 10))
        capture("account-quick-edit-confirmed")
    }
    @MainActor func testBatchSelectionRequiresConfirmationAndReportsEveryObject() {
        launchAndLogin()
        defer { capture("account-batch-final") }
        app.tabBars.buttons["账号"].tap()
        XCTAssertTrue(app.buttons["account.1"].waitForExistence(timeout: 10))
        app.buttons["accounts.more"].tap()
        XCTAssertTrue(app.buttons["account.2"].waitForExistence(timeout: 10))
        app.buttons["accounts.select"].tap()
        app.buttons["选择已加载账号"].tap()
        app.buttons["accounts.batch-actions"].tap()
        app.buttons["暂停调度"].tap()
        XCTAssertTrue(app.buttons["确认执行"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["批量操作结果"].exists)
        app.buttons["确认执行"].tap()
        XCTAssertTrue(app.navigationBars["批量操作结果"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["测试上游 A（#1）"].exists)
        XCTAssertTrue(app.staticTexts["测试上游 B（#2）"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "未发送服务器写入")).firstMatch.exists)
        capture("account-batch-object-results")
    }
    @MainActor private func launchAndLogin() {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing"]; app.launch()
        XCTAssertTrue(app.textFields["login.name"].waitForExistence(timeout: 10))
        enter("账号管理验收", in: app.textFields["login.name"])
        enter("https://account-management.example.invalid", in: app.textFields["login.url"])
        enter("manager@example.invalid", in: app.textFields["login.email"])
        enter("fixture-password", in: app.secureTextFields["login.password"])
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10))
    }
    @MainActor private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    @MainActor private func enter(_ text: String, in field: XCUIElement) { reveal(field); field.tap(); field.typeText(text) }
    @MainActor private func reveal(_ element: XCUIElement, down: Bool = true) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            let frame = app.frame
            let top = max(frame.minY + 100, app.navigationBars.firstMatch.frame.maxY + 20)
            let keyboard = app.keyboards.firstMatch
            let bottom = min(frame.maxY - 100, keyboard.exists ? keyboard.frame.minY - 20 : frame.maxY - 100)
            let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.15))
            let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.85))
            (down ? lower : upper).press(forDuration: 0.05, thenDragTo: down ? upper : lower)
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription)
    }
    @MainActor private func capture(_ title: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = title; screenshot.lifetime = .keepAlways; add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = title + "-accessibility"; hierarchy.lifetime = .keepAlways; add(hierarchy)
    }
}
