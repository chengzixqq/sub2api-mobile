import XCTest

/// S6-08: back in the foreground each compensation of the connected address is checked once, read-only (60 §19.4 step 9, X34).
/// Fixtures: `-ui-pending-compensation-here` gives Alice a $10.00 compensation of this site (0C…01); `-ui-pending-old-site` Bob's
/// $8.00 one of an older login at this address (0B…03); `-ui-pending-money` 王小明's of another address (0A…03); `-ui-reconcile-*`
/// decides what the check finds (AppModel+BalanceReconcile). Helpers follow SettingsUITests (S6D1-15).
final class CompensationForegroundUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!
    private static let grantHere = "0C000000-0000-4000-8000-000000000001"
    private static let oldLoginGrant = "0B000000-0000-4000-8000-000000000003"
    private static let oldLoginBatch = "0B000000-0000-4000-8000-000000000002"
    private static let otherAddressGrant = "0A000000-0000-4000-8000-000000000003"

    @MainActor func testForegroundCheckClearsIssuedCompensation() {
        launchAndLogin(arguments: ["-ui-pending-compensation-here", "-ui-reconcile-executed"])
        defer { diagnostics("compensation-foreground-issued-final") }
        app.openSitesSettings()
        let check = element("settings.pending.check.\(Self.grantHere)")
        reveal(check)
        backgroundAndReturn()
        XCTAssertTrue(waitForReceipt("已核对：已向 Alice 发放 $10.00 余额"), app.debugDescription)
        XCTAssertTrue(waitUntilGone(element("settings.pending.compensation.\(Self.grantHere)")), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
    }

    @MainActor func testForegroundCheckKeepsUnissuedCompensation() {
        launchAndLogin(arguments: ["-ui-pending-compensation-here", "-ui-reconcile-notfound"])
        defer { diagnostics("compensation-foreground-kept-final") }
        app.openSitesSettings()
        let check = element("settings.pending.check.\(Self.grantHere)")
        reveal(check)
        backgroundAndReturn()
        // Nothing found is never settled on its own and asks nothing until the administrator checks.
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(check.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.staticTexts["receipt.text"].exists, app.debugDescription)
    }

    @MainActor func testForegroundCheckCoversSameAddressOldLoginOnly() {
        launchAndLogin(arguments: ["-ui-pending-money", "-ui-pending-old-site", "-ui-reconcile-executed"])
        defer { diagnostics("compensation-foreground-old-login-final") }
        app.openSitesSettings()
        reveal(element("settings.pending.check.\(Self.oldLoginGrant)"))
        backgroundAndReturn()
        // The balance records go first (S3-07), so the last receipt is the compensation's.
        XCTAssertTrue(waitForReceipt("已核对：已向 Bob 发放 $8.00 余额"), app.debugDescription)
        // The batch next to it stays (60 §11.6), so the list still shows where the compensation was.
        reveal(element("settings.pending.check.\(Self.oldLoginBatch)"), towardBottom: false)
        XCTAssertFalse(element("settings.pending.compensation.\(Self.oldLoginGrant)").exists, app.debugDescription)
        // Another address is never checked from here (D17).
        reveal(element("settings.pending.web.\(Self.otherAddressGrant)"))
        XCTAssertFalse(app.alerts.firstMatch.exists, app.debugDescription)
    }

    // MARK: Helpers

    @MainActor private func backgroundAndReturn() {
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), app.debugDescription)
    }
    @MainActor private func waitForReceipt(_ text: String) -> Bool {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text), object: app.staticTexts["receipt.text"])
        return XCTWaiter().wait(for: [shown], timeout: 15) == .completed
    }
    @MainActor private func launchAndLogin(arguments: [String] = [], name: String = "设置站点", url: String = "https://settings.example.invalid") {
        continueAfterFailure = false
        app = XCUIApplication(); app.launchArguments = ["-ui-testing"] + arguments; app.launch()
        fillLogin(name: name, url: url)
    }
    @MainActor private func fillLogin(name: String, url: String) {
        XCTAssertTrue(element("login.name").waitForExistence(timeout: 10), app.debugDescription)
        enter(name, in: "login.name")
        enter(url, in: "login.url")
        enter("admin@example.com", in: "login.email")
        enter("fixture-password", in: "login.password")
        let submit = app.buttons["login.submit"]; reveal(submit); submit.tap()
        XCTAssertTrue(app.tabBars.buttons["概览"].waitForExistence(timeout: 10), app.debugDescription)
    }
    @MainActor private func waitUntilGone(_ item: XCUIElement) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: item)
        return XCTWaiter().wait(for: [gone], timeout: 10) == .completed
    }
    @MainActor private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }
    @MainActor private func enter(_ text: String, in identifier: String) {
        let field = element(identifier); reveal(field); field.tap(); field.typeText(text)
    }
    /// Rows of a List exist only near the screen; the row must end up between the navigation bar and the tab bar.
    @MainActor private func reveal(_ item: XCUIElement, towardBottom: Bool = true) {
        for _ in 0..<10 {
            if item.exists && item.isHittable && isAboveTabBar(item) { return }
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
    @MainActor private func isAboveTabBar(_ item: XCUIElement) -> Bool {
        guard app.tabBars.firstMatch.exists else { return true }
        return item.frame.maxY <= app.tabBars.firstMatch.frame.minY && item.frame.minY >= app.navigationBars.firstMatch.frame.maxY
    }
    @MainActor private func diagnostics(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription); tree.name = name + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
    }
}
