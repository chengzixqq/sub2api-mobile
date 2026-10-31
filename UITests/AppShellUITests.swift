import XCTest

/// S0-19: what the stage 0 shell tests did not cover yet — the sign-in method line for each way in (60 §3.3, on the
/// -ui-testing fixtures for access tokens and Admin Keys; passwords are SettingsUITests') and the root alert's error
/// details (00 §3.4, `-ui-switch-rejected`).
final class AppShellUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testSignInMethodsAreLabelledAndARefusedSwitchOffersDetails() {
        launch(["-ui-switch-rejected"])
        defer { diagnostics("app-shell-final") }
        signIn(site: "令牌站点", url: "https://token.example.invalid", key: "sat_ui-fixture")
        app.openSitesSettings()
        assertText("settings.current.auth", contains: "访问令牌 · 读写")
        XCTAssertFalse(element("settings.current.operator").exists, app.debugDescription)
        tap(app.buttons["settings.add"])
        signIn(site: "密钥站点", url: "https://key.example.invalid", key: "ui-admin-key")
        app.openSitesSettings()
        assertText("settings.current.auth", contains: "Admin Key · 以第一个管理员身份操作")
        assertText("settings.current.operator", contains: "以 admin@example.com 身份操作（第一个管理员）")

        tap(app.buttons["settings.site.令牌站点"], towardBottom: false)
        let alert = app.alerts["操作未完成"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), app.debugDescription)
        // iOS 27 exposes each alert button twice; both are the same control.
        XCTAssertTrue(alert.buttons["知道了"].firstMatch.exists, app.debugDescription)
        alert.buttons["详情"].firstMatch.tap()
        XCTAssertTrue(element("error.details.status").waitForExistence(timeout: 5), app.debugDescription)
        assertText("error.details.status", contains: "403")
        assertText("error.details.reason", contains: "FORBIDDEN")
        assertText("error.details.request-id", contains: "ui-fixture-request-id")
        let time = text(of: element("error.details.time"))
        XCTAssertNotNil(time.range(of: #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"#, options: .regularExpression), time)
        XCTAssertTrue(app.buttons["error.details.copy"].exists, app.debugDescription)
        diagnostics("error-details")
        app.buttons["error.details.done"].tap()
        XCTAssertTrue(element("error.details.status").waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(alert.exists)
        // A refused switch keeps the connected site.
        let current = app.buttons["settings.site.密钥站点"]
        reveal(current, towardBottom: false)
        XCTAssertEqual(current.value as? String, "当前", app.debugDescription)
    }

    @MainActor func testReadOnlyAccessTokenIsLabelledReadOnly() {
        launch(["-ui-readonly-token"])
        defer { diagnostics("app-shell-read-only") }
        signIn(site: "只读站点", url: "https://read-only.example.invalid", key: "sat_ui-fixture")
        app.openSitesSettings()
        assertText("settings.current.auth", contains: "访问令牌 · 只读")
    }

    // MARK: - Helpers

    @MainActor private func launch(_ arguments: [String]) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launchQuietly()
    }
    /// The root login page or the 添加站点 sheet; a `sat_` key switches the method to 管理访问令牌 on its own (60 §4.3).
    @MainActor private func signIn(site name: String, url: String, key: String) {
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10), app.debugDescription)
        enter(url, in: app.textFields["login.url"])
        enter(name, in: app.textFields["login.name"])
        tap(app.buttons["login.method.adminKey"])
        enter(key, in: app.secureTextFields["login.key"])
        if app.keyboards.firstMatch.exists {
            app.typeText("\n")
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        }
        tap(submit)
        XCTAssertTrue(submit.waitForNonExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func text(of item: XCUIElement) -> String { item.label + " " + (item.value as? String ?? "") }
    @MainActor private func assertText(_ identifier: String, contains expected: String, file: StaticString = #filePath, line: UInt = #line) {
        let item = element(identifier)
        reveal(item)
        XCTAssertTrue(text(of: item).contains(expected), text(of: item), file: file, line: line)
    }
    @MainActor private func tap(_ item: XCUIElement, towardBottom: Bool = true) { reveal(item, towardBottom: towardBottom); item.tap() }
    @MainActor private func enter(_ value: String, in field: XCUIElement) { tap(field); field.typeText(value) }
    /// Rows must end up between the navigation bar and the tab bar, which covers the last rows while they report hittable.
    @MainActor private func reveal(_ item: XCUIElement, towardBottom: Bool = true) {
        for _ in 0..<8 {
            if item.exists && item.isHittable && isClearOfBars(item) { return }
            let frame = app.frame
            let top = max(frame.minY + 100, app.navigationBars.firstMatch.frame.maxY + 20)
            let tabTop = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame.minY - 20 : frame.maxY - 100
            let bottom = min(tabTop, app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 20 : frame.maxY - 100)
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            let lower = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.85))
            let upper = origin.withOffset(CGVector(dx: 0, dy: top + (bottom - top) * 0.25))
            let down = towardBottom && !(item.exists && item.frame.maxY < top)
            (down ? lower : upper).press(forDuration: 0.05, thenDragTo: down ? upper : lower)
        }
        XCTAssertTrue(item.exists && item.isHittable, app.debugDescription)
    }
    @MainActor private func isClearOfBars(_ item: XCUIElement) -> Bool {
        let belowNavigation = !app.navigationBars.firstMatch.exists || item.frame.minY >= app.navigationBars.firstMatch.frame.maxY
        let aboveTabs = !app.tabBars.firstMatch.exists || item.frame.maxY <= app.tabBars.firstMatch.frame.minY
        return belowNavigation && aboveTabs
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
