import XCTest

final class Sub2MobileUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!
    @MainActor private func launch() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
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

    @MainActor func testLoginDashboardAccountPaginationAndDetails() {
        launch()
        login(name: "站点 A", url: "https://a.example.com")
        XCTAssertTrue(app.otherElements["dashboard.metrics"].waitForExistence(timeout: 10) || app.staticTexts["今日请求"].exists)
        app.tabBars.buttons["账号"].tap()
        XCTAssertTrue(app.buttons["account.1"].waitForExistence(timeout: 10))
        app.buttons["accounts.more"].tap()
        XCTAssertTrue(app.buttons["account.2"].waitForExistence(timeout: 10))
        app.buttons["account.1"].tap()
        reveal(app.buttons["account.test"])
        app.buttons["account.test"].tap()
        XCTAssertTrue(app.buttons["account.test.start"].waitForExistence(timeout: 5))
        // Opening the screen never launches a test or performs a server write.
        XCTAssertFalse(app.staticTexts["测试成功"].exists)
    }

    @MainActor func testUserPaginationAndMaskedKeys() {
        launch()
        login(name: "站点 A", url: "https://a.example.com")
        app.tabBars.buttons["用户"].tap()
        XCTAssertTrue(app.buttons["user.1"].waitForExistence(timeout: 10))
        app.buttons["users.more"].tap()
        XCTAssertTrue(app.buttons["user.2"].waitForExistence(timeout: 10))
        app.buttons["user.1"].tap()
        reveal(app.staticTexts["开发密钥"])
        XCTAssertTrue(app.staticTexts["••••••••cret"].exists)
        XCTAssertFalse(app.staticTexts["sk-fixture-secret"].exists)
        reveal(app.buttons["user.balance"])
    }

    @MainActor func testAddAndSwitchStations() {
        launch()
        login(name: "站点 A", url: "https://a.example.com")
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.add"].tap()
        login(name: "站点 B", url: "https://b.example.com")
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["settings.site.站点 A"].waitForExistence(timeout: 10))
        app.buttons["settings.site.站点 A"].tap()
        app.tabBars.buttons["概览"].tap()
        XCTAssertTrue(app.navigationBars["站点 A"].waitForExistence(timeout: 10))
    }

    @MainActor func testSameStationKeepsNewLoginAsSeparateIdentity() {
        launch()
        login(name: "管理员 A", url: "https://same.example.com")
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.add"].tap()
        login(name: "管理员 B", url: "https://same.example.com")
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["settings.site.管理员 A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.site.管理员 B"].exists)
    }

    @MainActor func testLogoutErasesCredentialInsteadOfRestoringSession() {
        launch()
        login(name: "站点 A", url: "https://a.example.com")
        app.tabBars.buttons["设置"].tap()
        app.buttons["settings.logout"].tap()
        app.buttons["退出并清除凭据"].tap()
        XCTAssertTrue(app.buttons["login.submit"].waitForExistence(timeout: 10))
        reveal(app.buttons["login.saved.站点 A"])
        app.buttons["login.saved.站点 A"].tap()
        XCTAssertTrue(app.alerts["操作未完成"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["此站点凭据已清除，请重新登录。"].exists)
        XCTAssertFalse(app.tabBars.buttons["概览"].exists)
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
        XCTAssertTrue(app.navigationBars["Sub2 Mobile"].waitForExistence(timeout: 10))
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
