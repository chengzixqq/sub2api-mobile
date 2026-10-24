import XCTest

/// S0-15: the settings page (60 §3) reached from the search directory, its local settings, the Face ID switch and threshold
/// (60 §3.4, U48, D36), the current site, deleting another site (D19) and the pending records of every site (R01).
final class SettingsUITests: XCTestCase {
    @MainActor private var app: XCUIApplication!

    @MainActor func testEntriesOpenTheSamePageUnderTheirTitles() {
        launchAndLogin()
        defer { diagnostics("settings-entries-final") }
        app.openSearchItem("search.item.interface")
        XCTAssertTrue(app.buttons["settings.mode.main"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.navigationBars["界面与模式"].exists, app.debugDescription)
        diagnostics("settings-interface")
        app.openSitesSettings()
        XCTAssertTrue(app.navigationBars["站点与凭据"].waitForExistence(timeout: 5), app.debugDescription)
        // Opened on 站点 (60 §3.1).
        XCTAssertTrue(app.buttons["settings.add"].isHittable, app.debugDescription)
        XCTAssertTrue(app.buttons["settings.site.设置站点"].exists, app.debugDescription)
        diagnostics("settings-sites")
    }

    @MainActor func testSimpleModeIsGreyedAndAppearanceIsOneChoice() {
        launchAndLogin()
        defer { diagnostics("settings-appearance-final") }
        app.openSearchItem("search.item.interface")
        let simple = app.buttons["settings.mode.simple"]
        XCTAssertTrue(simple.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(simple.isEnabled)
        XCTAssertTrue(simple.label.contains("设计中"), simple.label)
        XCTAssertTrue(app.buttons["settings.mode.main"].isSelected)
        let system = app.buttons["settings.appearance.system"], dark = app.buttons["settings.appearance.dark"]
        reveal(dark)
        XCTAssertTrue(system.isSelected)
        dark.tap()
        XCTAssertTrue(dark.isSelected, app.debugDescription)
        XCTAssertFalse(system.isSelected)
        diagnostics("settings-dark")
        system.tap()
        XCTAssertTrue(system.isSelected)
    }

    @MainActor func testFaceIDSwitchVerifiesAndShowsTheThreshold() {
        launchAndLogin()
        defer { diagnostics("settings-faceid-final") }
        app.openSearchItem("search.item.interface")
        let toggle = faceIDSwitch()
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(app.buttons["settings.faceid.threshold"].exists)
        tapSwitch(toggle)
        let threshold = app.buttons["settings.faceid.threshold"]
        XCTAssertTrue(threshold.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertTrue(threshold.label.contains("$100"), threshold.label)
        diagnostics("settings-faceid-on")
        setThreshold("250")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "settings.faceid.threshold", "$250"))
            .firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        // Turning it off is verified too (U48); the threshold row goes with it.
        tapSwitch(toggle)
        XCTAssertTrue(waitUntilGone(threshold), app.debugDescription)
        XCTAssertEqual(toggle.value as? String, "0")
    }

    @MainActor func testDeniedCheckKeepsTheSwitchOff() {
        launchAndLogin(arguments: ["-ui-biometric-deny"])
        defer { diagnostics("settings-faceid-denied") }
        app.openSearchItem("search.item.interface")
        let toggle = faceIDSwitch()
        tapSwitch(toggle)
        XCTAssertFalse(app.buttons["settings.faceid.threshold"].waitForExistence(timeout: 2))
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    @MainActor func testUnavailableDeviceGreysTheSwitch() {
        launchAndLogin(arguments: ["-ui-biometric-unavailable", "-ui-faceid-on"])
        defer { diagnostics("settings-faceid-unavailable") }
        app.openSearchItem("search.item.interface")
        let toggle = faceIDSwitch()
        XCTAssertFalse(toggle.isEnabled)
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertTrue(toggle.label.contains("这台设备没有设置 Face ID / 触控 ID"), toggle.label)
        XCTAssertFalse(app.buttons["settings.faceid.threshold"].exists)
    }

    @MainActor func testThresholdSheetTakesWholeDollarsFromOneToOneHundredThousand() {
        launchAndLogin(arguments: ["-ui-faceid-on"])
        defer { diagnostics("settings-threshold-range") }
        app.openSearchItem("search.item.interface")
        openThresholdSheet()
        let save = app.buttons["settings.threshold.save"]
        let field = app.textFields["settings.threshold.field"]
        XCTAssertTrue(save.isEnabled)
        // D22 keypad rule: the key that would pass 100,000 is refused, so "100001" stops at "10000".
        for (typed, shown, enabled) in [("0", "0", false), ("100001", "10000", true), ("1", "1", true), ("100000", "100000", true)] {
            replaceThreshold(with: typed)
            XCTAssertEqual(field.value as? String, shown, typed)
            XCTAssertEqual(save.isEnabled, enabled, typed)
        }
        diagnostics("settings-threshold-sheet")
        app.buttons["取消"].tap()
    }

    /// D36: a higher threshold needs the check, a lower one does not.
    @MainActor func testRaisingTheThresholdNeedsTheCheckLoweringDoesNot() {
        launchAndLogin(arguments: ["-ui-faceid-on", "-ui-biometric-deny"])
        defer { diagnostics("settings-threshold-raise-denied") }
        app.openSearchItem("search.item.interface")
        openThresholdSheet()
        replaceThreshold(with: "500")
        app.buttons["settings.threshold.save"].tap()
        // The check failed: the sheet stays, nothing is said, the old value is kept.
        XCTAssertTrue(app.textFields["settings.threshold.field"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.buttons["取消"].tap()
        let threshold = app.buttons["settings.faceid.threshold"]
        XCTAssertTrue(threshold.waitForExistence(timeout: 5))
        XCTAssertTrue(threshold.label.contains("$100"), threshold.label)
        setThreshold("50")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "settings.faceid.threshold", "$50"))
            .firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor func testCurrentSiteShowsIdentitySignInAndEntries() {
        launchAndLogin()
        defer { diagnostics("settings-current-site") }
        app.openSitesSettings()
        let identity = element("settings.current.identity")
        reveal(identity)
        XCTAssertTrue(identity.label.contains("admin@example.com · 管理员"), identity.label)
        XCTAssertTrue(element("settings.current.auth").label.contains("邮箱和密码"), element("settings.current.auth").label)
        reveal(element("settings.current.version"))
        XCTAssertTrue(element("settings.current.version").label.contains("ui-test"))
        // 00 §6.3: the zone line shows only when the phone's offset differs from the fixture's UTC+8.
        let differs = TimeZone.current.secondsFromGMT() != 8 * 3_600
        XCTAssertEqual(element("settings.current.timezone").exists, differs, app.debugDescription)
        let sessions = app.buttons["settings.current.sessions"]
        reveal(sessions)
        XCTAssertTrue(sessions.label.contains("3"), sessions.label)
        XCTAssertTrue(app.buttons["settings.current.tokens"].label.contains("2"), app.buttons["settings.current.tokens"].label)
        reveal(app.buttons["settings.logout"])
        diagnostics("settings-current-site-rows")
        sessions.tap()
        XCTAssertTrue(element("route.placeholder").waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.navigationBars["登录设备"].exists, app.debugDescription)
    }

    @MainActor func testDeletingAnotherSiteKeepsTheCurrentOneWithAReceipt() {
        launchAndLogin(name: "站点 A", url: "https://a.example.invalid")
        defer { diagnostics("settings-remove-other-final") }
        app.openSitesSettings()
        app.buttons["settings.add"].tap()
        fillLogin(name: "站点 B", url: "https://b.example.invalid")
        app.openSitesSettings()
        let more = app.buttons["settings.site.more.站点 A"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), app.debugDescription)
        more.tap()
        XCTAssertTrue(app.buttons["删除站点和凭据"].waitForExistence(timeout: 5))
        app.buttons["删除站点和凭据"].tap()
        // The confirmation dialog repeats the action as its destructive button.
        XCTAssertTrue(app.buttons["删除站点和凭据"].waitForExistence(timeout: 5))
        app.buttons["删除站点和凭据"].tap()
        let receipt = app.staticTexts["receipt.text"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(receipt.label, "已删除站点")
        XCTAssertTrue(waitUntilGone(app.buttons["settings.site.站点 A"]), app.debugDescription)
        XCTAssertTrue(app.buttons["settings.site.站点 B"].exists)
        XCTAssertTrue(app.buttons["settings.site.站点 B"].value as? String == "当前", app.debugDescription)
    }

    @MainActor func testPendingRecordsOfEverySite() {
        launchAndLogin(arguments: ["-ui-pending-money"])
        defer { diagnostics("settings-pending-final") }
        app.openSitesSettings()
        let refund = element("settings.pending.check.0A000000-0000-4000-8000-000000000001")
        reveal(refund)
        for title in ["退款结果待核对", "兑换码生成结果待核对"] {
            XCTAssertTrue(app.staticTexts[title].exists, title + "\n" + app.debugDescription)
        }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "设置站点 · Alice · ")).firstMatch.exists, app.debugDescription)
        XCTAssertTrue(element("settings.pending.check.0A000000-0000-4000-8000-000000000002").exists)
        // The deleted site's record points to its Web admin instead.
        let web = element("settings.pending.web.0A000000-0000-4000-8000-000000000003")
        reveal(web)
        XCTAssertTrue(app.staticTexts["补偿结果待核对"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "旧站点 · 王小明 · ")).firstMatch.exists, app.debugDescription)
        XCTAssertFalse(element("settings.pending.paused").exists)
        diagnostics("settings-pending")
        reveal(refund, towardBottom: false)
        refund.tap()
        XCTAssertTrue(app.navigationBars["Alice"].waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor func testUnreadablePendingFileShowsThePausedNotice() {
        launchAndLogin(arguments: ["-ui-pending-money", "-ui-pending-unreadable"])
        defer { diagnostics("settings-pending-paused") }
        app.openSearchItem("search.item.interface")
        let paused = element("settings.pending.paused")
        XCTAssertTrue(paused.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(paused.label.contains("兑换码"), paused.label)
        reveal(element("settings.pending.check.0A000000-0000-4000-8000-000000000001"))
        XCTAssertFalse(element("settings.pending.check.0A000000-0000-4000-8000-000000000002").exists)
    }

    // MARK: Helpers

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
    @MainActor private func faceIDSwitch() -> XCUIElement {
        let toggle = app.switches["settings.faceid"]
        reveal(toggle)
        return toggle
    }
    @MainActor private func tapSwitch(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -36, dy: 0)).tap()
    }
    @MainActor private func openThresholdSheet() {
        let threshold = app.buttons["settings.faceid.threshold"]
        reveal(threshold)
        threshold.tap()
        XCTAssertTrue(app.textFields["settings.threshold.field"].waitForExistence(timeout: 5), app.debugDescription)
    }
    @MainActor private func replaceThreshold(with text: String) {
        let field = app.textFields["settings.threshold.field"]
        field.tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: max(current.count, 6)) + text)
    }
    @MainActor private func setThreshold(_ text: String) {
        openThresholdSheet()
        replaceThreshold(with: text)
        app.buttons["settings.threshold.save"].tap()
        XCTAssertTrue(waitUntilGone(app.textFields["settings.threshold.field"]), app.debugDescription)
    }
    @MainActor private func waitUntilGone(_ item: XCUIElement) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: item)
        return XCTWaiter().wait(for: [gone], timeout: 5) == .completed
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
