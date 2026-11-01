import XCTest

/// 00 §7.5 (S6-23): `-ui-push-tap <type>[:<id>]@<站点名>` taps a notification with the backend's payload about 300 ms after the
/// site connects (`-ui-push-tap-when` names another site to wait for), through the same parsing and routing as the system's.
/// Fixture ids (来源 LiveOpsFixtureIDs and the account fixtures; the UI tests cannot import the App): alert 41, accounts 7 and 1.
final class PushRoutingUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testAlertTapOpensAlertDetailOnOverview() {
        launch(["-ui-push-tap", "ops_alert.fired:41@推送站点"])
        login(name: "推送站点", url: "https://push.example.invalid")
        XCTAssertTrue(element("alert.detail.status").waitForExistence(timeout: 15), app.debugDescription)
        goBack()
        XCTAssertTrue(app.navigationBars["推送站点"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testAccountErrorTapOpensAccountDetail() {
        launch(["-ui-push-tap", "account.error:7@推送站点"])
        login(name: "推送站点", url: "https://push.example.invalid")
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 15), app.debugDescription)
    }

    /// No result page reads a run by its id yet, and the test sheet would start another test: this session ran none, so only
    /// the detail opens.
    @MainActor func testTestFinishedTapOpensAccountDetailWithoutStartingATest() {
        launch(["-ui-push-tap", "account.test_finished:1@推送站点"])
        login(name: "推送站点", url: "https://push.example.invalid")
        XCTAssertTrue(element("account.detail.card").waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(element("account.test.sheet").waitForExistence(timeout: 2), app.debugDescription)
    }

    /// 设置 → 推送通知 on the overview tab; S6-24's page keeps the placeholder's title.
    @MainActor func testPushTestTapOpensPushSettings() {
        launch(["-ui-push-tap", "push.test@推送站点"])
        login(name: "推送站点", url: "https://push.example.invalid")
        XCTAssertTrue(app.navigationBars["推送通知"].waitForExistence(timeout: 15), app.debugDescription)
        goBack()
        XCTAssertTrue(app.navigationBars["界面与模式"].waitForExistence(timeout: 10), app.debugDescription)
    }

    /// Tapped while 站点 B is connected: 站点 A is switched to first, then its alert opens.
    @MainActor func testTapForAnotherSiteSwitchesBeforeOpening() {
        launch(["-ui-push-tap", "ops_alert.fired:41@站点 A", "-ui-push-tap-when", "站点 B"])
        login(name: "站点 A", url: "https://a.example.invalid")
        app.openSitesSettings()
        app.buttons["settings.add"].tap()
        login(name: "站点 B", url: "https://b.example.invalid")
        XCTAssertTrue(element("alert.detail.status").waitForExistence(timeout: 20), app.debugDescription)
        goBack()
        XCTAssertTrue(app.navigationBars["站点 A"].waitForExistence(timeout: 10), app.debugDescription)
    }

    /// A site this phone does not have, or a type the App does not know: the App only opens, and stays on the overview.
    @MainActor func testTapForUnknownSiteOrTypeStaysOnOverview() {
        for arguments in [["-ui-push-tap", "ops_alert.fired:41@没有这个站点", "-ui-push-tap-when", "推送站点"],
                          ["-ui-push-tap", "custom.event:1@推送站点"]] {
            launch(arguments)
            login(name: "推送站点", url: "https://push.example.invalid")
            XCTAssertTrue(element("home.ticker").waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertFalse(element("alert.detail.status").waitForExistence(timeout: 3), app.debugDescription)
            XCTAssertTrue(app.navigationBars["推送站点"].exists, app.debugDescription)
        }
    }

    // MARK: Helpers

    @MainActor private func launch(_ arguments: [String]) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launchQuietly()
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func goBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
        back.tap()
    }
    @MainActor private func login(name: String, url: String) {
        XCTAssertTrue(app.textFields["login.name"].waitForExistence(timeout: 10), app.debugDescription)
        enter(name, in: app.textFields["login.name"], towardBottom: false)
        enter(url, in: app.textFields["login.url"])
        enter("admin@example.com", in: app.textFields["login.email"])
        enter("fixture-password", in: app.secureTextFields["login.password"])
        if app.keyboards.firstMatch.exists { scroll(towardBottom: true) }
        reveal(app.buttons["login.submit"])
        app.buttons["login.submit"].tap()
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription)
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
        XCTAssertTrue(element.exists && element.isHittable, "\(element) not reached", file: file, line: line)
    }
    /// Above the keyboard, so the drag scrolls the form instead of typing.
    @MainActor private func scroll(towardBottom: Bool) {
        let frame = app.frame
        let bar = app.navigationBars.firstMatch
        let top = max(frame.minY + 100, bar.exists ? bar.frame.maxY + 20 : frame.minY + 100)
        let keyboard = app.keyboards.firstMatch
        let bottom = min(frame.maxY - 100, keyboard.exists ? keyboard.frame.minY - 20 : frame.maxY - 100)
        let height = max(40, bottom - top)
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
        let upper = origin.withOffset(CGVector(dx: 0, dy: top - frame.minY + height * 0.15))
        let lower = origin.withOffset(CGVector(dx: 0, dy: top - frame.minY + height * 0.85))
        (towardBottom ? lower : upper).press(forDuration: 0.05, thenDragTo: towardBottom ? upper : lower)
    }
}
