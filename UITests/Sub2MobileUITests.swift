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
        XCTAssertTrue(app.buttons["login.submit"].waitForExistence(timeout: 10))
        app.buttons["login.submit"].tap()
        XCTAssertTrue(app.staticTexts["login.error"].exists)
        enter("测试站点", in: app.textFields["login.name"])
        enter("http://example.com", in: app.textFields["login.url"])
        app.buttons["login.submit"].tap()
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
        XCTAssertTrue(app.buttons["account.test"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.buttons["user.balance"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["sk-fixture-secret"].exists)
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

    @MainActor private func login(name: String, url: String) {
        XCTAssertTrue(app.textFields["login.name"].waitForExistence(timeout: 10))
        enter(name, in: app.textFields["login.name"])
        enter(url, in: app.textFields["login.url"])
        enter("admin@example.com", in: app.textFields["login.email"])
        enter("fixture-password", in: app.secureTextFields["login.password"])
        // Submit may lie below the keyboard on small iPhones.
        app.swipeUp()
        app.buttons["login.submit"].tap()
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10))
    }
    @MainActor private func enter(_ value: String, in field: XCUIElement) { field.tap(); field.typeText(value) }
}
